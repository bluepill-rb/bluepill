module Bluepill
  class Process
    # Moves a Process between its states
    #
    # A process is unmonitored, up, down, starting, stopping or restarting.
    # Ticks and the start, stop, unmonitor and restart events move it, and
    # TransitionCallbacks run on the way.
    #
    # @api private
    module StateMachine
      # Where a tick moves a process from each state: to the first state if
      # it's running, or to the second if it isn't
      #
      # Unmonitored is the one state a tick doesn't change. Down means bluepill
      # knows the process isn't running, and unmonitored means it doesn't
      # care. A process that's stopping and still running failed to stop, so
      # a tick shows it as up.
      TICKS = {
        starting: %i[up down],
        up: %i[up down],
        stopping: %i[up down],
        down: %i[up starting],
        restarting: %i[up down]
      }.freeze

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

      # Every state a process can be in, since unmonitor leaves any of them
      STATES = TRANSITIONS.fetch(:unmonitor).keys.freeze

      # The transition from each state to itself, made once, so a tick that
      # leaves the state alone makes no new object
      LOOPBACKS = Hash[STATES.zip(STATES.collect { |state| Transition.new(state, state).freeze })].freeze

      # Return the process's state, such as :up
      #
      # @return [Symbol]
      #
      # @api private
      attr_accessor :state

      # Return whether the process is unmonitored
      #
      # @return [Boolean]
      #
      # @api private
      def unmonitored?
        state.equal?(:unmonitored)
      end

      # Return whether the process is up
      #
      # @return [Boolean]
      #
      # @api private
      def up?
        state.equal?(:up)
      end

      # Return whether the process is down
      #
      # @return [Boolean]
      #
      # @api private
      def down?
        state.equal?(:down)
      end

      # Return whether the process is starting
      #
      # @return [Boolean]
      #
      # @api private
      def starting?
        state.equal?(:starting)
      end

      # Return whether the process is stopping
      #
      # @return [Boolean]
      #
      # @api private
      def stopping?
        state.equal?(:stopping)
      end

      # Return whether the process is restarting
      #
      # @return [Boolean]
      #
      # @api private
      def restarting?
        state.equal?(:restarting)
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
        from = state
        to = event.equal?(:tick) ? tick_target(from) : TRANSITIONS.fetch(event)[from]
        return false unless to

        transition = from.equal?(to) ? LOOPBACKS.fetch(from) : Transition.new(from, to)
        return false unless catch(:halt) { before_transition(transition) }

        self.state = to
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
          self.state = :up
          return
        end
        self.state = auto_start.equal?(false) ? :unmonitored : :down # we need to check for false value
      end
    end
  end
end
