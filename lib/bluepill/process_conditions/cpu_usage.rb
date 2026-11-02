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
    class CpuUsage < BelowThreshold
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
    end
  end
end
