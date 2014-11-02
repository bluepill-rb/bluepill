module Bluepill
  module ProcessConditions
    class CpuUsage < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
      end

      def run(pid, include_children)
        # third col in the ps axu output
        System.cpu_usage(pid, include_children).to_f
      end

      def check(value)
        value < @below
      end
    end
  end
end
