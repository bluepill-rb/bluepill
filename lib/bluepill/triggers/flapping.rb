# frozen_string_literal: true

module Bluepill
  # The triggers a process can have
  #
  # @api private
  module Triggers
    # Stops a process that keeps restarting, and retries it later
    #
    # A config names it `checks :flapping`, with times: how many starts or
    # restarts count as flapping (5 by default), within: the seconds they
    # must happen in (1 by default), and retry_in: the seconds to wait before
    # starting the process again (5 by default, and 0 never to retry). When
    # the process flaps, the trigger unmonitors it, and starts it again
    # after retry_in.
    #
    # @example
    #   process.checks :flapping, times: 2, within: 30.seconds, retry_in: 7.seconds
    #
    # @api private
    class Flapping < Bluepill::Trigger
      # The states that a start or a restart moves the process to
      #
      # @api private
      TRIGGER_STATES = %i[starting restarting].freeze

      # Return how many starts or restarts count as flapping
      #
      # @return [Integer] the number of transitions
      #
      # @api private
      attr_accessor :times

      # Return the seconds the starts or restarts must happen in to flap
      #
      # @return [Integer] the seconds
      #
      # @api private
      attr_accessor :within

      # Return the seconds to wait before starting a flapping process again
      #
      # @return [Integer] the seconds, or 0 never to start it again
      #
      # @api private
      attr_accessor :retry_in

      # Return when the last starts and restarts happened
      #
      # @return [Util::RotationalArray<Integer>] their times, in seconds
      #
      # @api private
      attr_reader :timeline

      # Create the trigger for a process
      #
      # @param [Process] process the process to watch
      # @param [Hash{Symbol => Object}] options the trigger's options, with
      #   :times, :within, :retry_in and :logger
      #
      # @return [void]
      #
      # @api private
      def initialize(process, options = {})
        @times = options.fetch(:times, 5)
        @within = options.fetch(:within, 1)
        @retry_in = options.fetch(:retry_in, 5)
        @timeline = Util::RotationalArray.new(@times)
        super
      end

      # Record a start or a restart, and check whether the process flaps
      #
      # @param [StateMachine::Transition] transition the transition, which
      #   the trigger records if it's to starting or restarting
      #
      # @return [void]
      #
      # @api private
      def notify(transition)
        return unless TRIGGER_STATES.include?(transition.to_name)

        timeline << Clock.now
        check_flapping
      end

      # Forget the recorded starts and cancel the scheduled events
      #
      # @return [void]
      #
      # @api private
      def reset!
        @timeline.clear
        super
      end

      # Unmonitor the process and schedule its retry, if it's flapping
      #
      # It flaps when the last times starts or restarts happened within
      # within seconds.
      #
      # @return [void]
      #
      # @raise [UncaughtThrowError] HALT, which the process catches to stop
      #   the transition that flapped
      #
      # @api private
      def check_flapping
        # The process has not flapped if we haven't encountered enough incidents
        return unless @timeline.length == times

        # Check if the incident happend within the timeframe
        return unless @timeline.last - @timeline.first <= within

        logger.info "Flapping detected: retrying in #{retry_in} seconds"

        schedule_event(:start, retry_in) unless retry_in.zero? # retry_in zero means "do not retry, ever"
        schedule_event(:unmonitor, 0)

        @timeline.clear

        # Keep the process from making the transition that flapped
        throw HALT
      end
    end
  end
end
