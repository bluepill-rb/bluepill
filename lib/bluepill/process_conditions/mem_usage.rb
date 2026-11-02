# frozen_string_literal: true

module Bluepill
  module ProcessConditions
    # Checks a process's memory usage (its resident set size)
    #
    # A config names it `checks :mem_usage`, with below: the most memory
    # that's fine, in bytes (100.megabytes, say), and include_children: true
    # to add the process's children to it.
    #
    # @example
    #   process.checks :mem_usage, every: 10.seconds, below: 100.megabytes, times: [3, 5]
    #
    # @api private
    class MemUsage < BelowThreshold
      # Read the process's memory usage from the tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] include_children whether to add its children's usage
      #
      # @return [Float] the usage in bytes, or 0.0 for a process ps doesn't
      #   list
      #
      # @api private
      def run(pid, include_children) = System.memory_usage(pid, include_children).to_f * Units::KILOBYTE

      # Format the usage in kilobytes, or in megabytes from a megabyte up
      #
      # @param [Float] value the bytes run read
      #
      # @return [String] the usage and its unit, such as "312KB" or "250MB"
      #
      # @api private
      def format_value(value)
        if value >= Units::MEGABYTE
          format("%dMB", (value / Units::MEGABYTE).round)
        else
          format("%dKB", value / Units::KILOBYTE)
        end
      end
    end
  end
end
