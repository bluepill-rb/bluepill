module Bluepill
  module ProcessConditions
    class RunningTime < ProcessCondition
      def initialize(options = {})
        super
        @below = options[:below]
      end

      def run(pid, _include_children)
        # Like the other ps conditions, a process missing from ps reads as 0
        System.running_time(pid).to_i
      end

      def check(value)
        value < @below
      end
    end
  end
end
