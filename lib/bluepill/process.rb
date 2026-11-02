require "bluepill/system"
require "bluepill/process_journal"
require "bluepill/process_commands"
require "bluepill/process/pid"

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
    include Pid

    # The options a config can set for a process
    CONFIGURABLE_ATTRIBUTES = [
      :pre_start_command,
      :start_command,
      :stop_command,
      :restart_command,

      :post_start_command,
      :pre_stop_command,
      :post_stop_command,
      :notify_command,
      :hook_timeout,

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
      :group_unmonitor_noblock

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
    # @return [Array<Trigger>]
    #
    # @api private
    attr_accessor :triggers

    # Return the time, in epoch seconds, before which ticks are skipped
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

    # Return the command run each time the process comes up after a start
    #
    # It runs when the process reaches up, after a start or a restart, so a
    # server that daemonizes itself has written its pid file by then.
    # <tt>{{PID}}</tt> in it is replaced with the process's pid. It runs in
    # the background, and a failure is only logged.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :post_start_command

    # Return the command run before the process is stopped, if any
    #
    # The stop waits for it to finish, for up to hook_timeout, when it's
    # killed, and then goes ahead either way. <tt>{{PID}}</tt> in it is replaced with the
    # process's pid.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :pre_stop_command

    # Return the command run after the process has stopped, if any
    #
    # It runs in the background once bluepill has cleaned up after the
    # process. <tt>{{PID}}</tt> in it is replaced with the pid that stopped.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :post_stop_command

    # Return the command run each time the process changes state, if any
    #
    # It runs in the background, with BLUEPILL_APP, BLUEPILL_GROUP,
    # BLUEPILL_PROCESS, BLUEPILL_FROM, BLUEPILL_TO, BLUEPILL_REASON and
    # BLUEPILL_PID in its environment. An app can set it for all its
    # processes.
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :notify_command

    # Return how long a hook command may run before bluepill kills it
    #
    # It applies to post_start_command, pre_stop_command, post_stop_command
    # and notify_command. The default is 30 seconds.
    #
    # @return [Integer, Float]
    #
    # @api private
    attr_accessor :hook_timeout

    # Return the name of the app the process belongs to
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :app_name

    # Return the name of the group the process belongs to, if any
    #
    # @return [String, nil]
    #
    # @api private
    attr_accessor :group_name

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

    # A process's move from one state to another, as triggers and the
    # transition callbacks see it
    #
    # @api private
    class Transition
      # Return the state the process is leaving
      #
      # @return [Symbol]
      #
      # @api private
      attr_reader :from_name

      # Return the state the process is going to
      #
      # @return [Symbol]
      #
      # @api private
      attr_reader :to_name

      # Create a transition between two states
      #
      # @param [Symbol] from_name the state the process is leaving
      # @param [Symbol] to_name the state the process is going to
      #
      # @return [void]
      #
      # @api private
      def initialize(from_name, to_name)
        @from_name = from_name
        @to_name = to_name
      end

      # Return whether the process stays in the same state
      #
      # @return [Boolean]
      #
      # @api private
      def loopback?
        from_name.equal?(to_name)
      end
    end

    # Where a tick moves a process from each state: to the first state if
    # it's running, or to the second if it isn't
    #
    # Unmonitored is the one state a tick doesn't change. Down means bluepill
    # knows the process isn't running, and unmonitored means it doesn't
    # care. A process that's stopping and still running failed to stop, so
    # a tick shows it as up.
    TICKS = {
      starting: [:up, :down],
      up: [:up, :down],
      stopping: [:up, :down],
      down: [:up, :starting],
      restarting: [:up, :down]
    }.freeze

    # The states that a start or restart moves a process through on its
    # way up, after which post_start_command runs
    STARTS = [:starting, :restarting].freeze

    # Where every other event moves a process from each state it can leave
    TRANSITIONS = {
      start: {unmonitored: :starting, down: :starting},
      stop: {up: :stopping},
      unmonitor: {
        unmonitored: :unmonitored, up: :unmonitored, down: :unmonitored,
        starting: :unmonitored, stopping: :unmonitored, restarting: :unmonitored
      },
      restart: {up: :restarting, down: :restarting}
    }.freeze

    # Return the process's state, such as "up"
    #
    # @return [String]
    #
    # @api private
    attr_accessor :state

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
      @on_start_timeout = "start"
      @hook_timeout = 30
      @group_start_noblock = @group_stop_noblock = @group_restart_noblock = @group_unmonitor_noblock = true
      @state = "unmonitored"

      CONFIGURABLE_ATTRIBUTES.each do |attribute_name|
        public_send("#{attribute_name}=", options.fetch(attribute_name)) if options.key?(attribute_name)
      end
    end

    # Check on the process once a tick
    #
    # Unless ticks are being skipped, fire the state machine's tick event, and
    # then, for a process that's up, run its watches and tick its children.
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

      fire_event(:tick)

      return unless up?

      run_watches

      return unless monitor_children?

      refresh_children!
      children.each(&:tick)
    end

    # Return whether the process is unmonitored
    #
    # @return [Boolean]
    #
    # @api private
    def unmonitored?
      state.eql?("unmonitored")
    end

    # Return whether the process is up
    #
    # @return [Boolean]
    #
    # @api private
    def up?
      state.eql?("up")
    end

    # Return whether the process is down
    #
    # @return [Boolean]
    #
    # @api private
    def down?
      state.eql?("down")
    end

    # Return whether the process is starting
    #
    # @return [Boolean]
    #
    # @api private
    def starting?
      state.eql?("starting")
    end

    # Return whether the process is stopping
    #
    # @return [Boolean]
    #
    # @api private
    def stopping?
      state.eql?("stopping")
    end

    # Return whether the process is restarting
    #
    # @return [Boolean]
    #
    # @api private
    def restarting?
      state.eql?("restarting")
    end

    # Start the process, if it's unmonitored or down
    #
    # @return [Boolean] whether the process moved to starting
    #
    # @api private
    def start
      fire_event(:start)
    end

    # Stop the process, if it's up
    #
    # @return [Boolean] whether the process moved to stopping
    #
    # @api private
    def stop
      fire_event(:stop)
    end

    # Stop monitoring the process, from any state
    #
    # @return [Boolean] whether the process moved to unmonitored
    #
    # @api private
    def unmonitor
      fire_event(:unmonitor)
    end

    # Restart the process, if it's up or down
    #
    # @return [Boolean] whether the process moved to restarting
    #
    # @api private
    def restart
      fire_event(:restart)
    end

    # Move the process to the state an event leads to from its state
    #
    # The before callbacks see the old state, and can throw :halt to cancel
    # the move. The after callbacks see the new one.
    #
    # @param [Symbol] event :tick, :start, :stop, :unmonitor or :restart
    #
    # @return [Boolean] whether the process moved, false when the event
    #   doesn't lead anywhere from its state or a callback halted it
    #
    # @api private
    def fire_event(event)
      from = state.to_sym
      to = event.equal?(:tick) ? tick_target(from) : TRANSITIONS.fetch(event)[from]
      return false unless to

      transition = Transition.new(from, to)
      return false unless catch(:halt) { before_transition(transition) }

      self.state = to.to_s
      after_transition(transition)
      true
    end

    # Return where a tick moves the process from a state
    #
    # @param [Symbol] from the process's state
    #
    # @return [Symbol, nil] the next state, or nil for unmonitored
    #
    # @api private
    def tick_target(from)
      targets = TICKS[from]
      return unless targets

      process_running? ? targets.first : targets.last
    end

    # Run the callbacks before a transition
    #
    # They tell the triggers, and clean up the threads of a stop on the way
    # out of stopping.
    #
    # @param [Transition] transition the move about to happen
    #
    # @return [true] so fire_event knows no callback halted
    #
    # @api private
    def before_transition(transition)
      notify_triggers(transition)
      clean_threads if transition.from_name.equal?(:stopping)
      true
    end

    # Run the callbacks after a transition
    #
    # They start, stop or restart the process for the state it reached, and
    # then record the transition. Then they run post_start_command when a
    # start or restart brought the process up, and notify_command when its
    # state changed, in that order, as state_machine ran them.
    #
    # @param [Transition] transition the move that happened
    #
    # @return [void]
    #
    # @api private
    def after_transition(transition)
      case transition.to_name
      when :starting then start_process
      when :stopping then stop_process
      when :restarting then restart_process
      end
      record_transition(transition)
      post_start_process if transition.to_name.equal?(:up) && STARTS.include?(transition.from_name)
      notify_transition(transition)
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
        # The reason, for notify_command
        @transition_reason = reason
        begin
          public_send(event)
        ensure
          @transition_reason = nil
        end
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
        logger.warning "Clearing child list"
        children.clear
      end
      logger.info "Going from #{transition.from_name} => #{transition.to_name}"
    end

    # Tell every trigger about a transition
    #
    # @param [#from_name, #to_name, #loopback?] transition the transition
    #
    # @return [void]
    #
    # @raise [StandardError] what a trigger raised, after logging it
    #
    # @api private
    def notify_triggers(transition)
      triggers.each do |trigger|
        begin
          trigger.notify(transition)
        rescue => e
          logger.err e.backtrace
          raise
        end
      end
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
    # @param [Symbol] name the trigger's name, such as :flapping
    # @param [Hash{Symbol => Object}] options the trigger's options
    #
    # @return [Array<Trigger>] the process's triggers
    #
    # @api private
    def add_trigger(name, options)
      triggers << Trigger[name].new(self, options.merge(logger: logger))
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
      now = Integer(Time.now)

      # Each check that's due runs in a thread of its own, so a slow one
      # doesn't hold up the others. One that isn't due would do nothing, so
      # it gets no thread.
      threads = [] #: Array[[ConditionWatch, Thread]]
      watches.each do |watch|
        threads << [watch, Thread.new { watch.run(actual_pid, now) }] if watch.due?(now)
      end

      @transitioned = false

      threads.each_with_object([]) do |(watch, thread), events|
        watch_events = thread.value #: Array[Symbol]
        next if watch_events.empty?

        logger.info "#{watch.name} dispatched: #{watch_events.join(",")}"
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
        self.state = "up"
        return
      end
      self.state = auto_start.equal?(false) ? "unmonitored" : "down" # we need to check for false value
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
      when "start"
        if process_running?(true)
          logger.warning("Refusing to re-run start command on an already running process.")
        else
          dispatch!(:start, "user initiated")
        end
      when "stop"
        stop_process
        dispatch!(:unmonitor, "user initiated")
      when "restart"
        # Through the state machine, like a check's restart, so the process
        # shows as restarting and post_start_command runs once it's up. A
        # state restart can't leave, such as unmonitored, restarts it directly.
        restart_process unless dispatch!(:restart, "user initiated")
      when "unmonitor"
        # When the user issues an unmonitor cmd, reset any triggers so that
        # scheduled events gets cleared
        triggers.each(&:reset!)
        dispatch!(:unmonitor, "user initiated")
      end
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

    # Skip ticks for a while, such as for a command's grace time
    #
    # The times add up, so a stop followed by a start, which is how
    # restart_process works without a restart_command, waits out both grace
    # times.
    #
    # @param [Integer, Float] seconds how long to skip ticks for
    #
    # @return [Integer] when ticks resume, in epoch seconds
    #
    # @api private
    def skip_ticks_for(seconds)
      self.skip_ticks_until = (skip_ticks_until || Integer(Time.now)) + Integer(seconds)
    end

    # Return whether ticks are being skipped
    #
    # @return [Boolean, nil]
    #
    # @api private
    def skipping_ticks?
      skip_ticks_until && skip_ticks_until > Integer(Time.now)
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

      logger.info "Existing children: #{@children.collect(&:actual_pid).join(",")}. Got new children: #{new_children_pids} for #{actual_pid}" unless new_children_pids.empty?

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
