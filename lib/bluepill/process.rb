# frozen_string_literal: true

require "bluepill/system"
require "bluepill/util/log_error"
require "bluepill/process_journal"
require "bluepill/process_commands"
require "bluepill/process/attributes"
require "bluepill/process/pid"
require "bluepill/process/children"
require "bluepill/process/transition"
require "bluepill/process/state_machine"
require "bluepill/process/transition_callbacks"
require "bluepill/process/watches"
require "bluepill/process/user_commands"

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
    include TransitionCallbacks
    include UserCommands

    # Return the process's name, which commands and logs use
    #
    # @return [String]
    #
    # @api private
    attr_accessor :name

    # Return the checks that run on the process every interval
    #
    # @return [Watches]
    #
    # @api private
    attr_reader :watches

    # Return the triggers notified of the process's transitions
    #
    # @return [Array<Trigger>]
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
    # @param [Hash{Symbol => Hash{Symbol => Object}}, Array<Array(Symbol, Hash{Symbol => Object})>]
    #   checks each check's name and options, as a Hash, or as a list of
    #   pairs, which can name a check twice
    # @param [Logger, nil] logger the process's logger
    # @param [Integer, nil] actual_pid the pid of a child process that's
    #   already running
    # @param [Hash{Symbol => Object}] attributes the process's attributes,
    #   of which those in CONFIGURABLE_ATTRIBUTES are set
    #
    # @return [void]
    #
    # @api private
    def initialize(process_name, checks, logger: nil, actual_pid: nil, **attributes)
      @name = process_name
      @event_mutex = Monitor.new
      @children = []
      @threads = []
      @statistics = ProcessStatistics.new
      @actual_pid = actual_pid
      add_checks(checks, logger)
      @state = :unmonitored
      configure(attributes)
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

      @skip_ticks_until = nil
      # clear the memoization per tick
      @process_running = nil
      # Deal with thread cleanup here since the stopping state isn't used
      clean_threads if unmonitored?
      fire_event(:tick)
      return unless up?

      run_watches
      tick_children if monitor_children?
    rescue => e
      Util.log_error(logger, "tick failed", e)
    end

    # Find the process's children, and tick each of them
    #
    # Each child's tick logs its own errors, so one that fails doesn't keep
    # the others from ticking.
    #
    # @return [void]
    #
    # @api private
    def tick_children
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
      watches.logger = logger
      triggers.each { |t| t.logger = logger }
    end

    # Record an event and fire it on the state machine
    #
    # @param [Symbol, String] event the event, one of
    #   StateMachine::TRANSITIONS, such as :start or :restart
    # @param [String, nil] reason why, for the process's event history
    #
    # @return [Boolean] whether the state machine made the transition
    #
    # @raise [KeyError] for an event that isn't one of
    #   StateMachine::TRANSITIONS, after recording it
    #
    # @api private
    def dispatch!(event, reason = nil)
      @event_mutex.synchronize do
        @statistics.record_event(event, reason)
        # The reason, for notify_command
        @transition_reason = reason
        begin
          # to_sym, until every caller gives a Symbol
          fire_event(event.to_sym)
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
    # @param [Hash{Symbol => Hash{Symbol => Object}}, Array<Array(Symbol, Hash{Symbol => Object})>]
    #   checks each check's name and options, as a Hash, or as a list of
    #   pairs, which can name a check twice
    # @param [Logger] logger the logger to use
    #
    # @return [void]
    #
    # @api private
    def add_checks(checks, logger)
      @watches = Watches.new
      @triggers = []
      self.logger = logger
      checks.each do |name, opts|
        if Trigger[name]
          add_trigger(name, **opts)
        else
          watches.add(name, **opts)
        end
      end
    end

    # Add a trigger to notify of the process's transitions
    #
    # @param [Symbol] name the trigger's name, such as :flapping
    # @param [Hash{Symbol => Object}] options the trigger's options
    #
    # @return [Array<Trigger>] the process's triggers
    #
    # @api private
    def add_trigger(name, **options)
      triggers << Trigger[name].new(self, **options, logger: logger)
    end

    # Run every watch that's due, and dispatch the events they fire
    #
    # Once an event changes the process's state, the events after it are
    # dropped, since the watches asked for them of the state it left.
    #
    # @return [void]
    #
    # @api private
    def run_watches
      events = watches.run(Clock.now) { actual_pid }
      return if events.empty?

      @transitioned = false
      events.each do |event, reason|
        break if @transitioned

        dispatch!(event, reason)
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
    def daemonize? = !!daemonize

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
    def skipping_ticks? = skip_ticks_until && skip_ticks_until > Clock.now
  end
end
