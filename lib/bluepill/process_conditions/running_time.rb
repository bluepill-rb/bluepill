module Bluepill
  module ProcessConditions
    class RunningTime < ProcessCondition
      def initialize(options = {})
        super
        @below = options[:below]
      end

      def run(pid, _include_children)
        System.running_time(pid)
      end

      def check(value)
        value < @below
      end
    end
  end
end
