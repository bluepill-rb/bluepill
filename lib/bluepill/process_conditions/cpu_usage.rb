module Bluepill
  module ProcessConditions
    # Checks a process's CPU usage, as a percentage
    #
    # A config names it `checks :cpu_usage`, with below: the highest
    # percentage that's fine, and include_children: true to add the
    # process's children to it.
    #
    # @example
    #   process.checks :cpu_usage, every: 10.seconds, below: 5, times: 3
    #
    # @api private
    class CpuUsage < ProcessCondition
      # Create the check
      #
      # @param [Hash{Symbol => Object}] options the check's options, with
      #   :below, the highest percentage that's fine
      #
      # @return [void]
      #
      # @api private
      def initialize(options = {})
        super
        @below = options[:below]
      end

      # Read the process's CPU usage from the tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] include_children whether to add its children's usage
      #
      # @return [Float] the percentage, or 0.0 for a process ps doesn't list
      #
      # @api private
      def run(pid, include_children)
        # third col in the ps axu output
        System.cpu_usage(pid, include_children).to_f
      end

      # Return whether the usage is below the limit
      #
      # @param [Float] value the percentage run read
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
