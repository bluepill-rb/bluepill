# fixes problem with loading on systems with rubyist-aasm installed
gem 'state_machine'

require 'state_machine'
require 'daemons'
require 'bluepill/system'
require 'bluepill/process_journal'
require 'bluepill/process_commands'

module Bluepill
  class Process
    include ProcessCommands

    CONFIGURABLE_ATTRIBUTES = [
      :pre_start_command,
      :start_command,
      :stop_command,
      :restart_command,

      :stdout,
      :stderr,
      :stdin,

      :daemonize,
      :pid_file,
      :working_dir,
      :environment,

      :start_grace_time,
      :stop_grace_time,
      :restart_grace_time,

      :uid,
      :gid,

      :cache_actual_pid,

      :monitor_children,
      :child_process_factory,

      :pid_command,
      :auto_start,

      :supplementary_groups,

      :stop_signals,

      :on_start_timeout,

      :group_start_noblock,
      :group_restart_noblock,
      :group_stop_noblock,
      :group_unmonitor_noblock,

    ].freeze

    attr_accessor :name, :watches, :triggers, :skip_ticks_until, :process_running, *CONFIGURABLE_ATTRIBUTES
    attr_reader :children, :statistics, :logger

    state_machine initial: :unmonitored do
      # These are the idle states, i.e. only an event (either external or internal) will trigger a transition.
      # The distinction between down and unmonitored is that down
      # means we know it is not running and unmonitored is that we don't care if it's running.
      state :unmonitored, :up, :down

      # These are transitionary states, we expect the process to change state after a certain period of time.
      state :starting, :stopping, :restarting

      event :tick do
        transition starting: :up, if: :process_running?
        transition starting: :down, unless: :process_running?

        transition up: :up, if: :process_running?
        transition up: :down, unless: :process_running?

        # The process failed to die after entering the stopping state. Change the state to reflect
        # reality.
        transition stopping: :up, if: :process_running?
        transition stopping: :down, unless: :process_running?

        transition down: :up, if: :process_running?
        transition down: :starting, unless: :process_running?

        transition restarting: :up, if: :process_running?
        transition restarting: :down, unless: :process_running?
      end

      event :start do
        transition [:unmonitored, :down] => :starting
      end

      event :stop do
        transition up: :stopping
      end

      event :unmonitor do
        transition any => :unmonitored
      end

      event :restart do
        transition [:up, :down] => :restarting
      end

      before_transition any => any, do: :notify_triggers
      before_transition stopping: any, do: :clean_threads

      after_transition any => :starting, do: :start_process
      after_transition any => :stopping, do: :stop_process
      after_transition any => :restarting, do: :restart_process

      after_transition any => any, do: :record_transition
    end

    def initialize(process_name, checks, options = {})
      @name = process_name
      @event_mutex = Monitor.new
      @watches = []
      @triggers = []
      @children = []
      @threads = []
      @statistics = ProcessStatistics.new
      @actual_pid = options[:actual_pid]
      self.logger = options[:logger]

      checks.each do |name, opts|
        if Trigger[name]
          add_trigger(name, opts)
        else
          add_watch(name, opts)
        end
      end

      # These defaults are overriden below if it's configured to be something else.
      @monitor_children = false
      @cache_actual_pid = true
      @start_grace_time = @stop_grace_time = @restart_grace_time = 3
      @environment = {}
      @on_start_timeout = 'start'
      @group_start_noblock = @group_stop_noblock = @group_restart_noblock = @group_unmonitor_noblock = true

      CONFIGURABLE_ATTRIBUTES.each do |attribute_name|
        public_send("#{attribute_name}=", options.fetch(attribute_name)) if options.key?(attribute_name)
      end

      # Let state_machine do its initialization stuff
      super() # no arguments intentional
    end

    def tick
      return if skipping_ticks?

      self.skip_ticks_until = nil

      # clear the memoization per tick
      @process_running = nil

      # Deal with thread cleanup here since the stopping state isn't used
      clean_threads if unmonitored?

      # run state machine transitions. state_machine defines tick in a
      # module it creates, which the signatures can't name.
      super # steep:ignore UnexpectedSuper

      return unless up?

      run_watches

      return unless monitor_children?

      refresh_children!
      children.each(&:tick)
    end

    def logger=(logger)
      @logger = logger
      watches.each { |w| w.logger = logger }
      triggers.each { |t| t.logger = logger }
    end

    # State machine methods
    def dispatch!(event, reason = nil)
      @event_mutex.synchronize do
        @statistics.record_event(event, reason)
        public_send(event)
      end
    end

    def record_transition(transition)
      return if transition.loopback?

      @transitioned = true

      # When a process changes state, we should clear the memory of all the watches
      watches.each(&:clear_history!)

      # Also, when a process changes state, we should re-populate its child list
      if monitor_children?
        logger.warning 'Clearing child list'
        children.clear
      end
      logger.info "Going from #{transition.from_name} => #{transition.to_name}"
    end

    def notify_triggers(transition)
      triggers.each do |trigger|
        begin
          trigger.notify(transition)
        rescue StandardError => e
          logger.err e.backtrace
          raise
        end
      end
    end

    # Watch related methods
    def add_watch(name, options)
      watches << ConditionWatch.new(name, options.merge(logger: logger))
    end

    def add_trigger(name, options)
      triggers << Trigger[name].new(self, options.merge(logger: logger))
    end

    def run_watches
      now = Integer(Time.now)

      threads = watches.collect do |watch|
        [watch, Thread.new { watch.run(actual_pid, now) }] #: [ConditionWatch, Thread]
      end

      @transitioned = false

      threads.each_with_object([]) do |(watch, thread), events|
        watch_events = thread.value #: Array[Symbol]
        next if watch_events.empty?

        logger.info "#{watch.name} dispatched: #{watch_events.join(',')}"
        watch_events.each do |event|
          events << [event, watch.to_s]
        end
      end.each do |event, reason| # rubocop:disable Style/MultilineBlockChain
        break if @transitioned

        dispatch!(event, reason)
      end
    end

    def determine_initial_state
      if process_running?(true)
        self.state = 'up'
        return
      end
      self.state = auto_start.equal?(false) ? 'unmonitored' : 'down' # we need to check for false value
    end

    def handle_user_command(cmd)
      case cmd
      when 'start'
        if process_running?(true)
          logger.warning('Refusing to re-run start command on an already running process.')
        else
          dispatch!(:start, 'user initiated')
        end
      when 'stop'
        stop_process
        dispatch!(:unmonitor, 'user initiated')
      when 'restart'
        restart_process
      when 'unmonitor'
        # When the user issues an unmonitor cmd, reset any triggers so that
        # scheduled events gets cleared
        triggers.each(&:reset!)
        dispatch!(:unmonitor, 'user initiated')
      end
    end

    # System Process Methods
    def process_running?(force = false)
      @process_running = nil if force # clear existing state if forced

      @process_running ||= signal_process(0)
      # the process isn't running, so we should clear the PID
      clear_pid unless @process_running
      @process_running #: bool
    end

    def clean_threads
      @threads.each(&:kill)
      @threads.clear
    end

    def daemonize?
      !!daemonize
    end

    def monitor_children?
      !!monitor_children
    end

    def signal_process(code)
      code = code.to_s.upcase if code.is_a?(String) || code.instance_of?(Symbol)
      pid = actual_pid
      # kill with a pid of 0 or less signals a whole process group, which
      # could include bluepill itself, so only signal a real pid
      raise "invalid pid #{pid.inspect}" unless pid && pid > 0

      ::Process.kill(code, pid)
      true
    rescue StandardError => e
      logger.err "Failed to signal process #{pid} with code #{code}: #{e}"
      false
    end

    def cache_actual_pid?
      !!@cache_actual_pid
    end

    def actual_pid
      pid_command ? pid_from_command : pid_from_file
    end

    def pid_from_file
      return @actual_pid if cache_actual_pid? && @actual_pid

      @actual_pid = if pid_file
                      if File.exist?(pid_file)
                        positive_pid(File.read(pid_file).to_i)
                      else
                        logger.warning("pid_file #{pid_file} does not exist or cannot be read")
                        nil
                      end
                    end
    end

    def pid_from_command
      # Output that is not just digits reads as nil, so as 0
      positive_pid(`#{pid_command}`.strip[/\A\d+\z/].to_i)
    end

    # An empty or garbled pid file reads as 0, which is never a real process
    def positive_pid(pid)
      pid if pid > 0
    end

    def actual_pid=(pid)
      ProcessJournal.append_pid_to_journal(name, pid) # be sure to always log the pid
      @actual_pid = pid
    end

    def clear_pid
      @actual_pid = nil
    end

    def unlink_pid
      System.delete_if_exists(pid_file)
    end

    # Internal State Methods
    def skip_ticks_for(seconds)
      # The times add up, so a stop followed by a start, which is how
      # restart_process works without a restart_command, waits out both grace times
      self.skip_ticks_until = (skip_ticks_until || Integer(Time.now)) + Integer(seconds)
    end

    def skipping_ticks?
      skip_ticks_until && skip_ticks_until > Integer(Time.now)
    end

    def refresh_children!
      # First prune the list of dead children
      @children.delete_if { |child| !child.process_running?(true) }

      # Add new found children to the list
      new_children_pids = System.get_children(actual_pid) - @children.collect(&:actual_pid)

      logger.info "Existing children: #{@children.collect(&:actual_pid).join(',')}. Got new children: #{new_children_pids} for #{actual_pid}" unless new_children_pids.empty?

      # Construct a new process wrapper for each new found children
      # monitor_children sets the factory
      factory = child_process_factory #: ProcessFactory
      new_children_pids.each do |child_pid|
        ProcessJournal.append_pid_to_journal(name, child_pid) if daemonize?
        child_name = "<child(pid:#{child_pid})>"
        child_logger = logger.prefix_with(child_name)

        child = factory.create_child_process(child_name, child_pid, child_logger)
        @children << child
      end
    end
  end
end
