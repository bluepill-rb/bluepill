# fixes problem with loading on systems with rubyist-aasm installed
gem 'state_machine'

require 'state_machine'
require 'daemons'
require 'bluepill/system'
require 'bluepill/process_journal'
require 'bluepill/process_commands'

module Bluepill
  # A process that bluepill monitors
  #
  # Its state machine moves it between unmonitored, up, down, starting,
  # stopping and restarting. Every tick checks that it's still running,
  # runs its watches, and fires the events they ask for.
  #
  # @api private
  class Process
    include ProcessCommands

    # The options a config can set for a process
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

    # Return the process's name, which commands and logs use
    #
    # @return [String]
    #
    # @api private
    attr_accessor :name

    # Return the checks that run on the process every interval
    #
    # @return [Array<ConditionWatch>]
    #
    # @api private
    attr_accessor :watches

    # Return the triggers notified of the process's transitions
    #
    # @return [Array<Trigger, Trigger::Custom>]
    #
    # @api private
    attr_accessor :triggers

    # Return the time, from Clock.now, before which ticks are skipped
    #
    # Set while a start, stop or restart command has its grace time to take
    # effect.
    #
    # @return [Integer, nil]
    #
    # @api private
    attr_accessor :skip_ticks_until

    # Return whether the process was running when last checked this tick
    #
    # tick clears it, so the first check of each tick signals the process.
    #
    # @return [Boolean, nil]
    #
    # @api private
    attr_accessor :process_running

    # Return the command run before every start, if any
    #
    # Bluepill waits for it to finish, and starts the process even if it exits
    # with a non-zero status. It runs in the process's working_dir, with its
    # environment, uid and gid.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :pre_start_command

    # Return the command that starts the process
    #
    # Bluepill splits it into words and runs it without a shell.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :start_command

    # Return the command that stops the process, if any
    #
    # <tt>{{PID}}</tt> in it is replaced with the process's pid. Without
    # one, bluepill sends stop_signals, or TERM.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :stop_command

    # Return the command that restarts the process, if any
    #
    # <tt>{{PID}}</tt> in it is replaced with the process's pid. Without
    # one, bluepill stops the process and starts it again.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :restart_command

    # Return the file a daemonized process's standard output goes to
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :stdout

    # Return the file a daemonized process's standard error goes to
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :stderr

    # Return the file a daemonized process's standard input comes from
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :stdin

    # Return whether bluepill daemonizes the process and writes its pid file
    #
    # Set it for a process that doesn't daemonize itself.
    #
    # @return [Boolean, nil]
    #
    # @api private
    attr_accessor :daemonize

    # Return the file that holds the process's pid
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :pid_file

    # Return the directory the process's commands run in
    #
    # A daemonized process starts in / unless this is set.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :working_dir

    # Return the environment variables the process's commands get
    #
    # @return [Hash{#to_s => #to_s}, nil]
    #
    # @api private
    attr_accessor :environment

    # Return how long to wait for the process to start, in seconds
    #
    # Bluepill skips ticks for this long after a start. The default is 3.
    #
    # @return [Integer, Float]
    #
    # @api private
    attr_accessor :start_grace_time

    # Return how long to wait for the process to stop, in seconds
    #
    # Bluepill skips ticks for this long after a stop. The default is 3.
    #
    # @return [Integer, Float]
    #
    # @api private
    attr_accessor :stop_grace_time

    # Return how long to wait for the process to restart, in seconds
    #
    # Bluepill skips ticks for this long after a restart. The default is 3.
    #
    # @return [Integer, Float]
    #
    # @api private
    attr_accessor :restart_grace_time

    # Return the user the process's commands run as
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :uid

    # Return the group the process's commands run as
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :gid

    # Return whether to read the pid file only until it gives a pid
    #
    # True by default. Set it to false for a process whose pid changes, such
    # as one checked for zombies.
    #
    # @return [Boolean]
    #
    # @api private
    attr_accessor :cache_actual_pid

    # Return whether bluepill also watches the process's children
    #
    # @return [Boolean]
    #
    # @api private
    attr_accessor :monitor_children

    # Return the factory that makes a Process for each child found
    #
    # monitor_children sets it, with the children's checks.
    #
    # @return [ProcessFactory, nil]
    #
    # @api private
    attr_accessor :child_process_factory

    # Return the command whose output is the process's pid, if any
    #
    # Used instead of pid_file when it's set.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :pid_command

    # Return whether bluepill starts the process when it loads
    #
    # Only false keeps it from starting: the process is then unmonitored.
    #
    # @return [Boolean, nil]
    #
    # @api private
    attr_accessor :auto_start

    # Return the extra groups the process's commands run with
    #
    # @return [Array<String>, nil]
    #
    # @api private
    attr_accessor :supplementary_groups

    # Return the signals that stop the process, with the delays between
    #
    # A signal, then a delay in seconds and a signal, and so on, such as
    # [:quit, 30, :term, 5, :kill]. Each later signal is only sent if the
    # process is still running.
    #
    # @return [Array<Symbol, Integer>, nil]
    #
    # @api private
    attr_accessor :stop_signals

    # Return the event to dispatch when the start command takes too long
    #
    # The default is start, which tries again.
    #
    # @return [String, Symbol]
    #
    # @api private
    attr_accessor :on_start_timeout

    # Return whether a group's start runs without waiting for this process
    #
    # @return [Boolean]
    #
    # @api private
    attr_accessor :group_start_noblock

    # Return whether a group's restart runs without waiting for this process
    #
    # @return [Boolean]
    #
    # @api private
    attr_accessor :group_restart_noblock

    # Return whether a group's stop runs without waiting for this process
    #
    # @return [Boolean]
    #
    # @api private
    attr_accessor :group_stop_noblock

    # Return whether a group's unmonitor runs without waiting for it
    #
    # @return [Boolean]
    #
    # @api private
    attr_accessor :group_unmonitor_noblock

    # Return the processes made for the process's children
    #
    # Only filled when monitor_children is set.
    #
    # @return [Array<Process>]
    #
    # @api private
    attr_reader :children

    # Return the process's recent events
    #
    # @return [ProcessStatistics]
    #
    # @api private
    attr_reader :statistics

    # Return the logger, prefixed with the process's name
    #
    # @return [Logger]
    #
    # @api private
    attr_reader :logger

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

    # Create a process from its checks and options
    #
    # Each check is a watch, or a trigger if one has its name. Options that
    # aren't given keep their defaults: 3 second grace times, a cached pid,
    # and children left alone.
    #
    # @param [String] process_name the process's name
    # @param [Hash{Symbol => Hash{Symbol => Object}}] checks options by
    #   check name
    # @param [Hash{Symbol => Object}] options the process's options, such as
    #   CONFIGURABLE_ATTRIBUTES, :logger and :actual_pid
    #
    # @return [void]
    #
    # @api private
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

    # Check on the process once a tick
    #
    # Unless ticks are being skipped, fire the state machine's tick event, and
    # then, for a process that's up, run its watches and tick its children.
    #
    # An error, such as one a trigger raised, is logged with its backtrace,
    # and the process ticks again next time, so one broken check or trigger
    # doesn't stop the daemon.
    #
    # @return [void]
    #
    # @api private
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
    rescue StandardError => e
      Util.log_error(logger, 'tick failed', e)
    end

    # Set the logger, for the process and for its watches and triggers
    #
    # @param [Logger] logger the logger to use
    #
    # @return [void]
    #
    # @api private
    def logger=(logger)
      @logger = logger
      watches.each { |w| w.logger = logger }
      triggers.each { |t| t.logger = logger }
    end

    # Record an event and fire it on the state machine
    #
    # @param [Symbol, String] event the event, such as :start or :restart
    # @param [String, nil] reason why, for the process's event history
    #
    # @return [Boolean] whether the state machine made the transition
    #
    # @api private
    def dispatch!(event, reason = nil)
      @event_mutex.synchronize do
        @statistics.record_event(event, reason)
        public_send(event)
      end
    end

    # Clear the watches' history after the process changes state
    #
    # A process that's monitoring its children also clears their list, so it
    # finds them again. A loopback, such as up to up, changes nothing.
    #
    # @param [#from_name, #to_name, #loopback?] transition the transition
    #
    # @return [void]
    #
    # @api private
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

    # Tell every trigger about a transition
    #
    # An error a trigger raises stops the transition, and tick logs it.
    #
    # @param [#from_name, #to_name, #loopback?] transition the transition
    #
    # @return [void]
    #
    # @raise [StandardError] what a trigger raised
    #
    # @api private
    def notify_triggers(transition)
      triggers.each { |trigger| trigger.notify(transition) }
    end

    # Add a check to run on the process every interval
    #
    # @param [Symbol] name the check's name, such as :mem_usage
    # @param [Hash{Symbol => Object}] options the check's options
    #
    # @return [Array<ConditionWatch>] the process's watches
    #
    # @api private
    def add_watch(name, options)
      watches << ConditionWatch.new(name, options.merge(logger: logger))
    end

    # Add a trigger to notify of the process's transitions
    #
    # A trigger that a config defines gets transitions that warn about what
    # bluepill 0.2.0's don't have. Bluepill's own, Flapping, gets them as
    # they are.
    #
    # @param [Symbol] name the trigger's name, such as :flapping
    # @param [Hash{Symbol => Object}] options the trigger's options
    #
    # @return [Array<Trigger, Trigger::Custom>] the process's triggers
    #
    # @api private
    def add_trigger(name, options)
      trigger = Trigger[name].new(self, options.merge(logger: logger))
      triggers << (trigger.instance_of?(Triggers::Flapping) ? trigger : Trigger::Custom.new(trigger))
    end

    # Run every watch, and dispatch the events they fire
    #
    # Each watch runs in a thread of its own. Once an event changes the
    # process's state, the events after it are dropped.
    #
    # @return [void]
    #
    # @api private
    def run_watches
      now = Clock.now

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

    # Set the state to up, down or unmonitored when bluepill loads
    #
    # A running process is up. Otherwise it's down, so that it starts, unless
    # auto_start is false.
    #
    # @return [void]
    #
    # @api private
    def determine_initial_state
      if process_running?(true)
        self.state = 'up'
        return
      end
      self.state = auto_start.equal?(false) ? 'unmonitored' : 'down' # we need to check for false value
    end

    # Carry out a command from the command line
    #
    # @param [String] cmd start, stop, restart or unmonitor
    #
    # @return [void]
    #
    # @api private
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
        # Through the state machine, like a check's restart, so the process
        # shows as restarting until it's up again. A state restart can't
        # leave, such as unmonitored, restarts it directly.
        restart_process unless dispatch!(:restart, 'user initiated')
      when 'unmonitor'
        # When the user issues an unmonitor cmd, reset any triggers so that
        # scheduled events gets cleared
        triggers.each(&:reset!)
        dispatch!(:unmonitor, 'user initiated')
      end
    end

    # Return whether the process is running, and forget its pid if not
    #
    # The answer is kept for the rest of the tick.
    #
    # @param [Boolean] force whether to check again this tick
    #
    # @return [Boolean]
    #
    # @api private
    def process_running?(force = false)
      @process_running = nil if force # clear existing state if forced

      @process_running ||= signal_process(0)
      # the process isn't running, so we should clear the PID
      clear_pid unless @process_running
      @process_running #: bool
    end

    # Kill the threads the process's commands left running
    #
    # @return [void]
    #
    # @api private
    def clean_threads
      @threads.each(&:kill)
      @threads.clear
    end

    # Return whether bluepill daemonizes the process
    #
    # @return [Boolean]
    #
    # @api private
    def daemonize?
      !!daemonize
    end

    # Return whether bluepill watches the process's children
    #
    # @return [Boolean]
    #
    # @api private
    def monitor_children?
      !!monitor_children
    end

    # Send a signal to the process
    #
    # A process without a pid isn't running, so it gets no signal and nothing
    # is logged. A failure is logged.
    #
    # @param [Integer, String, Symbol] code the signal, such as 0 or :term
    #
    # @return [Boolean] whether the signal was sent
    #
    # @api private
    def signal_process(code)
      code = code.to_s.upcase if code.is_a?(String) || code.instance_of?(Symbol)
      pid = actual_pid
      # Without a pid the process isn't running. That's expected before the
      # first start, and actual_pid already warns about a missing pid file.
      return false unless pid

      # kill with a pid of 0 or less signals a whole process group, which
      # could include bluepill itself, so only signal a real pid
      raise "invalid pid #{pid}" unless pid > 0

      ::Process.kill(code, pid)
      true
    rescue StandardError => e
      logger.err "Failed to signal process #{pid} with code #{code}: #{e}"
      false
    end

    # Return whether the pid is kept once it's read
    #
    # @return [Boolean]
    #
    # @api private
    def cache_actual_pid?
      !!@cache_actual_pid
    end

    # Return the process's pid, from pid_command or the pid file
    #
    # @return [Integer, nil] the pid, or nil if there's none yet
    #
    # @api private
    def actual_pid
      pid_command ? pid_from_command : pid_from_file
    end

    # Return the pid in the pid file, cached unless cache_actual_pid is false
    #
    # A missing pid file is logged as a warning.
    #
    # @return [Integer, nil] the pid, or nil without a pid file or a pid
    #
    # @api private
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

    # Return the pid that pid_command prints
    #
    # Output that isn't only digits gives no pid.
    #
    # @return [Integer, nil] the pid, or nil if the output isn't one
    #
    # @api private
    def pid_from_command
      # Output that is not just digits reads as nil, so as 0
      positive_pid(`#{pid_command}`.strip[/\A\d+\z/].to_i)
    end

    # Return the pid, unless it's 0 or less
    #
    # An empty or garbled pid file reads as 0, which is never a real process.
    #
    # @param [Integer] pid the pid that was read
    #
    # @return [Integer, nil] the pid, or nil if it's not a real one
    #
    # @api private
    def positive_pid(pid)
      pid if pid > 0
    end

    # Set the pid, and add it to the process's journal
    #
    # @param [Integer] pid the process's pid
    #
    # @return [void]
    #
    # @api private
    def actual_pid=(pid)
      ProcessJournal.append_pid_to_journal(name, pid) # be sure to always log the pid
      @actual_pid = pid
    end

    # Forget the process's pid
    #
    # @return [nil]
    #
    # @api private
    def clear_pid
      @actual_pid = nil
    end

    # Delete the pid file, if there is one
    #
    # @return [void]
    #
    # @api private
    def unlink_pid
      System.delete_if_exists(pid_file)
    end

    # Skip ticks for a while, such as for a command's grace time
    #
    # The times add up, so a stop followed by a start, which is how
    # restart_process works without a restart_command, waits out both grace
    # times.
    #
    # @param [Integer, Float] seconds how long to skip ticks for
    #
    # @return [Integer] when ticks resume, from Clock.now
    #
    # @api private
    def skip_ticks_for(seconds)
      self.skip_ticks_until = (skip_ticks_until || Clock.now) + Integer(seconds)
    end

    # Return whether ticks are being skipped
    #
    # @return [Boolean, nil]
    #
    # @api private
    def skipping_ticks?
      skip_ticks_until && skip_ticks_until > Clock.now
    end

    # Update the list of children from the tick's ps table
    #
    # Children that are no longer running are dropped, and a Process is made
    # for each new one, with the checks monitor_children gave.
    #
    # @return [void]
    #
    # @api private
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
