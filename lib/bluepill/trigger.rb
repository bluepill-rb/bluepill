module Bluepill
  # Reacts to a process's state transitions, as one of a process's checks
  #
  # A config names a trigger the way it names a check, by its underscored
  # class name: `checks :flapping` makes a Triggers::Flapping. Subclasses
  # register themselves by that name, and implement notify.
  #
  # @api private
  class Trigger
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
      @implementations[klass.name.split('::').last.underscore.to_sym] = klass
    end

    # Return the trigger class a config names
    #
    # @param [Symbol] name the trigger's underscored name, such as :flapping
    #
    # @return [Class, nil] the Trigger subclass, or nil when no trigger has
    #   that name (so the name is a check's)
    #
    # @api private
    def self.[](name)
      @implementations[name]
    end

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

    # Return the lock that guards the scheduled events
    #
    # @return [Thread::Mutex] the lock
    #
    # @api private
    attr_accessor :mutex

    # Return the events the trigger scheduled, each with its thread
    #
    # @return [Array<Array(Symbol, Thread)>] each event and the thread that
    #   dispatches it
    #
    # @api private
    attr_accessor :scheduled_events

    # Create a trigger for a process
    #
    # @param [Process] process the process to watch
    # @param [Hash{Symbol => Object}] options the trigger's options, with
    #   :logger
    #
    # @return [void]
    #
    # @api private
    def initialize(process, options = {})
      self.process = process
      self.logger = options[:logger]
      self.mutex = Mutex.new
      self.scheduled_events = []
    end

    # Cancel the events the trigger scheduled, as when the user unmonitors
    #
    # @return [void]
    #
    # @api private
    def reset!
      cancel_all_events
    end

    # React to a state transition, before it happens
    #
    # @param [StateMachine::Transition] _transition the transition
    #
    # @return [void]
    #
    # @raise [RuntimeError] unless a subclass implements it
    #
    # @api private
    def notify(_transition)
      raise 'Implement in subclass'
    end

    # Send an event to the process, with the trigger's name as the reason
    #
    # @param [Symbol] event the event, such as :start
    #
    # @return [Boolean] whether the process made the transition
    #
    # @api private
    def dispatch!(event)
      process.dispatch!(event, self.class.name.split('::').last)
    end

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
        thread = Thread.new do
          begin
            sleep delay.to_f
            dispatch!(event)
            mutex.synchronize do
              scheduled_events.delete_if { |_, t| t.equal?(Thread.current) }
            end
          rescue StandardError => e
            logger.err(e)
            logger.err(e.backtrace.to_a.join("\n"))
          end
        end
        scheduled_events.push([event, thread])
        thread
      end
    end

    # Cancel every scheduled event, killing its thread
    #
    # @return [void]
    #
    # @api private
    def cancel_all_events
      logger.info 'Canceling all scheduled events'
      mutex.synchronize do
        scheduled_events.collect(&:last).each(&:kill)
        scheduled_events.clear
      end
    end
  end
end
