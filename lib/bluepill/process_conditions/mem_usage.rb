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
    class MemUsage < ProcessCondition
      # The bytes in a megabyte, from which a value shows in megabytes
      #
      # @api private
      MB         = (1024**2) #: Integer

      # How a value shows in the history: a number and its unit
      #
      # @api private
      FORMAT_STR = '%d%s'.freeze

      # The unit of a value that shows in megabytes
      #
      # @api private
      MB_LABEL   = 'MB'.freeze

      # The unit of a value that shows in kilobytes
      #
      # @api private
      KB_LABEL   = 'KB'.freeze

      # Create the check
      #
      # @param [Hash{Symbol => Object}] options the check's options, with
      #   :below, the most memory that's fine, in bytes
      #
      # @return [void]
      #
      # @api private
      def initialize(options = {})
        super
        @below = options[:below]
      end

      # Read the process's memory usage from the tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] include_children whether to add its children's usage
      #
      # @return [Float] the usage in kilobytes, or 0.0 for a process ps
      #   doesn't list
      #
      # @api private
      def run(pid, include_children)
        # rss is on the 5th col
        System.memory_usage(pid, include_children).to_f
      end

      # Return whether the usage is below the limit
      #
      # A limit that can't be compared counts as fine.
      #
      # @param [Float] value the kilobytes run read
      #
      # @return [Boolean] true when it's below the limit
      #
      # @api private
      def check(value)
        value * 1024 < @below
      rescue StandardError
        true
      end

      # Format the usage in kilobytes, or in megabytes from a megabyte up
      #
      # @param [Float] value the kilobytes run read
      #
      # @return [String] the usage and its unit, such as "312KB" or "250MB"
      #
      # @api private
      def format_value(value)
        if value * 1024 >= MB
          format(FORMAT_STR, (value / 1024).round, MB_LABEL)
        else
          format(FORMAT_STR, value, KB_LABEL)
        end
      end
    end
  end
end
