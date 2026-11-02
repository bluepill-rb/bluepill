# frozen_string_literal: true

module Bluepill
  # Reacts to a process's state transitions, as one of a process's checks
  #
  # A config names a trigger the way it names a check, by its underscored
  # class name: `checks :flapping` makes a Triggers::Flapping. Subclasses
  # register themselves by that name, and implement notify.
  #
  # @api private
  class Trigger
    # The symbol a trigger throws from notify to stop the transition it was
    # told of. The process catches it and stays in its state.
    #
    # @api private
    HALT = :halt

    @implementations = {}

    # Register a subclass by its underscored name, such as :flapping
    #
    # @param [Class] klass the subclass
    #
    # @return [void]
    #
    # @api private
    def self.inherited(klass)
      super
      @implementations[Util.underscore(klass.name.split("::").last).to_sym] = klass
    end

    # Return the trigger class a config names
    #
    # @param [Symbol] name the trigger's underscored name, such as :flapping
    #
    # @return [Class, nil] the Trigger subclass, or nil when no trigger has
    #   that name (so the name is a check's)
    #
    # @api private
    def self.[](name) = @implementations[name]

    # Return the process the trigger watches
    #
    # @return [Process] the process
    #
    # @api private
    attr_accessor :process

    # Return the logger the trigger writes to
    #
    # @return [Logger] the process's logger
    #
    # @api private
    attr_accessor :logger

    # Return the events the trigger scheduled, each with its thread
    #
    # Read them under the lock, since their threads remove them as they
    # finish.
    #
    # @return [Array<Array(Symbol, Thread)>] each event and the thread that
    #   dispatches it
    #
    # @api private
    attr_reader :scheduled_events

    # Create a trigger for a process
    #
    # @param [Process] process the process to watch
    # @param [Logger, nil] logger the process's logger
    #
    # @return [void]
    #
    # @raise [ArgumentError] for an option that no trigger takes
    #
    # @api private
    def initialize(process, logger: nil)
      self.process = process
      self.logger = logger
      @mutex = Mutex.new
      @scheduled_events = []
      # The reason the trigger gives the process for what it dispatches,
      # such as "Flapping"
      @reason = self.class.name.split("::").last
    end

    # Cancel the events the trigger scheduled, as when the user unmonitors
    #
    # @return [void]
    #
    # @api private
    def reset! = cancel_all_events

    # React to a state transition, before it happens
    #
    # @param [StateMachine::Transition] _transition the transition
    #
    # @return [void]
    #
    # @raise [RuntimeError] unless a subclass implements it
    #
    # @api private
    def notify(_transition) = raise("Implement in subclass")

    # Send an event to the process, with the trigger's name as the reason
    #
    # @param [Symbol] event the event, such as :start
    #
    # @return [Boolean] whether the process made the transition
    #
    # @api private
    def dispatch!(event) = process.dispatch!(event, @reason)

    # Dispatch an event after a delay, in a thread of its own
    #
    # @param [Symbol] event the event, such as :start
    # @param [Numeric] delay the seconds to wait first
    #
    # @return [Thread] the thread that waits and dispatches
    #
    # @api private
    def schedule_event(event, delay)
      mutex.synchronize do
        thread = Thread.new { run_scheduled_event(event, delay) }
        scheduled_events.push([event, thread])
        thread
      end
    end

    # Wait, dispatch a scheduled event, and forget it, in its own thread
    #
    # An error is logged, since nothing joins the thread to see it.
    #
    # @param [Symbol] event the event, such as :start
    # @param [Numeric] delay the seconds to wait first
    #
    # @return [void]
    #
    # @api private
    def run_scheduled_event(event, delay)
      # Kernel.sleep, not sleep, so the specs can stand in for the clock.
      # Float takes a duration, through its to_f, but not nil.
      Kernel.sleep(Float(delay))
      dispatch!(event)
      mutex.synchronize do
        scheduled_events.delete_if { |_, t| t.equal?(Thread.current) }
      end
    rescue => e
      logger.err(e)
      logger.err(e.backtrace.to_a.join("\n"))
    end

    # Cancel every scheduled event, killing its thread
    #
    # @return [void]
    #
    # @api private
    def cancel_all_events
      logger.info "Canceling all scheduled events"
      mutex.synchronize do
        scheduled_events.collect(&:last).each(&:kill)
        scheduled_events.clear
      end
    end

    private

    # Return the lock that guards the scheduled events
    #
    # @return [Thread::Mutex] the lock
    #
    # @api private
    attr_reader :mutex
  end
end
