module Bluepill
  class Trigger
    # A trigger that a config defines, as a process's triggers hold it
    #
    # It hands the trigger each transition wrapped in a {Transition}, which
    # warns when the trigger reads what bluepill 0.2.0's transitions don't
    # have. Bluepill's own trigger only reads what they have, so the process
    # holds it as it is, and its transitions cost nothing more.
    #
    # @api private
    class Custom
      # Return the trigger the config defined
      #
      # @return [Trigger]
      #
      # @api private
      attr_reader :trigger

      # Wrap a trigger that a config defined
      #
      # @param [Trigger] trigger the trigger
      #
      # @return [void]
      #
      # @api private
      def initialize(trigger)
        @trigger = trigger
      end

      # Tell the trigger about a transition, wrapped in a Transition
      #
      # The wrapper warns about what bluepill 0.2.0's transitions lack.
      #
      # @param [StateMachine::Transition] transition the transition
      #
      # @return [void]
      #
      # @api private
      def notify(transition)
        trigger.notify(Transition.new(transition, trigger.class))
      end

      # Cancel the trigger's scheduled events
      #
      # @return [void]
      #
      # @api private
      def reset!
        trigger.reset!
      end

      # Set the logger the trigger writes to
      #
      # @param [Logger] logger the process's logger
      #
      # @return [void]
      #
      # @api private
      def logger=(logger)
        trigger.logger = logger
      end
    end

    # A transition, as a trigger that a config defines gets it
    #
    # Bluepill 0.2.0 gives a trigger's notify a transition with only
    # from_name, to_name and loopback?. This one answers everything
    # state_machine's does, but warns about anything else a trigger calls,
    # such as from, to or event.
    #
    # @api private
    class Transition
      # Wrap a transition
      #
      # @param [StateMachine::Transition] transition the transition
      # @param [Class] trigger_class the trigger's class, which the warning
      #   names
      #
      # @return [void]
      #
      # @api private
      def initialize(transition, trigger_class)
        @transition = transition
        @trigger_class = trigger_class
      end

      # Return the state the process is leaving
      #
      # @return [Symbol]
      #
      # @api private
      def from_name
        @transition.from_name
      end

      # Return the state the process is going to
      #
      # @return [Symbol]
      #
      # @api private
      def to_name
        @transition.to_name
      end

      # Return whether the process stays in the same state
      #
      # @return [Boolean]
      #
      # @api private
      def loopback?
        @transition.loopback?
      end

      # Call one of the transition's other methods, with a warning
      #
      # @param [Symbol] name the method, such as :event
      # @param [Array<Object>] args its arguments
      # @param [Proc, nil] block its block
      #
      # @return [Object] what the transition's method returns
      #
      # @raise [NoMethodError] for a method the transition doesn't have
      #
      # @api private
      def method_missing(name, *args, &block)
        # The transition raises NoMethodError for a method it doesn't have
        result = @transition.public_send(name, *args, &block)
        message = "bluepill 0.2.0 gives a trigger's notify a transition with only from_name, to_name and loopback?, " \
                  "so #{@trigger_class}'s call of its #{name} fails there. Use from_name, to_name or loopback? instead."
        Deprecation.warn([@trigger_class, name], message)
        result
      end

      # Return whether the transition has a method
      #
      # @param [Symbol] name the method's name
      # @param [Boolean] include_private whether to count private methods
      #
      # @return [Boolean]
      #
      # @api private
      def respond_to_missing?(name, include_private)
        @transition.respond_to?(name, include_private)
      end
    end
  end
end
