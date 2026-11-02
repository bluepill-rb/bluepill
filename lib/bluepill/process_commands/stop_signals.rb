# frozen_string_literal: true

module Bluepill
  module ProcessCommands
    # Stops a Process with its stop_signals: a signal, then a delay and a
    # signal, and so on, until the process stops
    #
    # @api private
    module StopSignals
      # Send the stop signals from a thread of their own, with their delays
      #
      # @param [Process::StopSignals] signals the signals, with the delays
      #   between
      #
      # @return [Array<Thread>] the process's threads, with the new one
      #
      # @api private
      def send_stop_signals_in_background(signals)
        logger.warning "Sending stop signals to #{actual_pid}"
        @threads << Thread.new { send_stop_signals(signals) }
      end

      # Send stop signals, with their delays, until the process stops
      #
      # Sends the first signal, then each later one after its delay, as long as
      # the process is still running. Then gives the last signal the rest of
      # stop_grace_time to work before cleaning up.
      #
      # @param [Process::StopSignals] signals the signals, with the delays
      #   between
      #
      # @return [void]
      #
      # @api private
      def send_stop_signals(signals)
        send_stop_signal(signals.first_signal)
        remaining = send_later_stop_signals(signals)
        wait_for_stop(remaining) if remaining
        cleanup_process
      end

      # Send each signal after the first, after its delay
      #
      # It stops once the process isn't running.
      #
      # @param [Process::StopSignals] signals the signals, with the delays
      #   between
      #
      # @return [Integer, Float, nil] how much of stop_grace_time is left, or
      #   nil if the process stopped
      #
      # @api private
      def send_later_stop_signals(signals)
        signals.later_signals.each do |delay, signal|
          return nil unless running_after?(delay)

          send_stop_signal(signal)
        end
        stop_grace_time - signals.total_delay
      end

      # Send one of the stop signals, and log it
      #
      # @param [Symbol] signal the signal
      #
      # @return [Boolean] whether the signal was sent
      #
      # @api private
      def send_stop_signal(signal)
        logger.info "Sending signal #{signal} to #{actual_pid}"
        signal_process(signal)
      end

      # Wait for a delay, and return whether the process is still running
      #
      # @param [Integer] delay how long to wait, in seconds
      #
      # @return [Boolean]
      #
      # @api private
      def running_after?(delay)
        logger.debug "Sleeping for #{delay} seconds"
        # Kernel.sleep, not sleep, so the specs can stand in for the clock
        Kernel.sleep(delay)
        return true if signal_process(0)

        logger.debug "Process has terminated."
        false
      end

      # Wait for the process to exit, checking once a second
      #
      # It stops 2 seconds short of the grace time: ticks resume up to a second
      # early (they count whole seconds) and can kill this thread, and the
      # cleanup itself takes up to another second.
      #
      # @param [Integer, Float] seconds the grace time that's left
      #
      # @return [void]
      #
      # @api private
      def wait_for_stop(seconds)
        (seconds - 2).ceil.times do
          break unless signal_process(0)

          Kernel.sleep(1)
        end
      end
    end
  end
end
