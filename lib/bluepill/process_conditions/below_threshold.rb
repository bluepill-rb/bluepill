module Bluepill
  module ProcessConditions
    # Checks that a value a process reads is below a limit
    #
    # The limit is the check's below: option. CpuUsage, MemUsage,
    # RunningTime and FileTime build on it, and implement run to read the
    # value.
    #
    # @api private
    class BelowThreshold < ProcessCondition
      # Create the check
      #
      # @param [Hash{Symbol => Object}] options the check's options, with
      #   :below, the limit
      #
      # @return [void]
      #
      # @api private
      def initialize(options = {})
        super
        @below = options[:below]
      end

      # Return whether a value is below the limit
      #
      # @param [Numeric] value what run read
      #
      # @return [Boolean] true when it's below the limit
      #
      # @api private
      def check?(value)
        value < @below
      end
    end
  end
end
