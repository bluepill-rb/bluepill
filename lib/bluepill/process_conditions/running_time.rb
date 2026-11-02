module Bluepill
  module ProcessConditions
    # Checks how long a process has been running, in seconds
    #
    # A config names it `checks :running_time`, with below: the longest the
    # process may run (24.hours, say), to restart a process that has run for
    # too long.
    #
    # @example
    #   process.checks :running_time, every: 10.minutes, below: 24.hours
    #
    # @api private
    class RunningTime < BelowThreshold
      # Read how long the process has run from the tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] _include_children whether to include its children
      #
      # @return [Integer] the seconds since it started
      #
      # @api private
      def run(pid, _include_children)
        # Like the other ps conditions, a process missing from ps reads as 0
        System.running_time(pid).to_i
      end
    end
  end
end
