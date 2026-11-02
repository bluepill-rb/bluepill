require "bluepill/system"
require "bluepill/process_journal"
require "bluepill/process_commands"
require "bluepill/process/attributes"
require "bluepill/process/pid"
require "bluepill/process/children"
require "bluepill/process/transition"
require "bluepill/process/state_machine"
require "bluepill/process/checks"

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
    include Attributes
    include Pid
    include Children
    include StateMachine
    include Checks

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
      @children = []
      @threads = []
      @statistics = ProcessStatistics.new
      @actual_pid = options[:actual_pid]
      add_checks(checks, options[:logger])
      @state = "unmonitored"
      configure(options)
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

    # Set the logger, and add each check
    #
    # A check is a trigger if one has its name, and a watch otherwise. Each
    # gets the logger.
    #
    # @param [Hash{Symbol => Hash{Symbol => Object}}] checks options by
    #   check name
    # @param [Logger] logger the logger to use
    #
    # @return [void]
    #
    # @api private
    def add_checks(checks, logger)
      @watches = []
      @triggers = []
      self.logger = logger
      checks.each do |name, opts|
        if Trigger[name]
          add_trigger(name, opts)
        else
          add_watch(name, opts)
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
  end
end
