# frozen_string_literal: true

module Bluepill
  class Process
    # The signals that stop a process, with the delays between them
    #
    # A pill file gives them as an Array that alternates signals and delays,
    # starting and ending with a signal, such as [:quit, 30, :term, 5, :kill]:
    # send QUIT, and if the process is still running 30 seconds later send
    # TERM, and if it's still running 5 seconds after that send KILL.
    #
    # @api private
    class StopSignals
      # Return stop signals, from an Array or as they are
      #
      # @example
      #   StopSignals.from([:quit, 30, :kill]).total_delay # => 30
      #
      # @param [StopSignals, Array<Symbol, Integer>] signals the stop signals,
      #   or the signals and delays
      #
      # @return [StopSignals]
      #
      # @raise [ConfigError] for an Array that doesn't alternate signals and
      #   delays
      #
      # @api private
      def self.from(signals) = signals.instance_of?(StopSignals) ? signals : new(signals)

      # Return the signal sent first
      #
      # @example
      #   StopSignals.new([:quit, 30, :kill]).first_signal # => :quit
      #
      # @return [Symbol]
      #
      # @api private
      attr_reader :first_signal

      # Return each signal after the first, with the delay before it
      #
      # @example
      #   StopSignals.new([:quit, 30, :term, 5, :kill]).later_signals
      #   # => [[30, :term], [5, :kill]]
      #
      # @return [Array<Array(Integer, Symbol)>] frozen pairs of the seconds to
      #   wait and the signal to send then
      #
      # @api private
      attr_reader :later_signals

      # Parse the signals and delays, and fail on a mistake
      #
      # @example
      #   StopSignals.new([:quit, 30, :term, 5, :kill])
      #
      # @param [Array<Symbol, Integer>] signals a signal, then a delay in
      #   seconds and a signal, and so on
      #
      # @return [void]
      #
      # @raise [ConfigError] unless the signals and delays alternate, starting
      #   and ending with a signal
      #
      # @api private
      def initialize(signals)
        validate!(signals)
        # validate! checked that signals alternate, starting with a signal
        @first_signal = signals.first #: Symbol
        @later_signals = signals.drop(1).each_slice(2).to_a.freeze #: Array[[Integer, Symbol]]
        freeze
      end

      # Return the delays added up
      #
      # @example
      #   StopSignals.new([:quit, 30, :term, 5, :kill]).total_delay # => 35
      #
      # @return [Integer] the seconds between the first signal and the last
      #
      # @api private
      def total_delay = later_signals.sum { |delay, _signal| delay }

      # Return the signals and delays, as a pill file gives them
      #
      # @example
      #   StopSignals.new([:quit, 30, :kill]).to_a # => [:quit, 30, :kill]
      #
      # @return [Array<Symbol, Integer>]
      #
      # @api private
      def to_a = [first_signal, *later_signals.flat_map(&:itself)]

      private

      # Fail unless the signals and delays alternate
      #
      # The signals and delays must alternate, starting and ending with a
      # signal. Checks the more specific problems before the 'odd number'
      # message.
      #
      # @param [Array<Symbol, Integer>] signals the signals and delays
      #
      # @return [void]
      #
      # @raise [ConfigError] for a mistake
      #
      # @api private
      def validate!(signals)
        signals.each_with_index do |value, i|
          expected, label = i.even? ? [Symbol, "a symbol (signal)"] : [Integer, "a number (delay)"]
          next if value.is_a?(expected)

          raise(ConfigError, "Config Error: Invalid stop_signals!  Expected #{label} at position #{i} instead of '#{value}'.")
        end
        raise(ConfigError, "Config Error: Invalid stop_signals!  Expected an odd number of elements.") unless signals.size.odd?
      end
    end
  end
end
