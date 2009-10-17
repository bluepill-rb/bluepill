module Bluepill
  module ProcessConditions
    class CpuUsage < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
      end
      
      def run(pid)
        # third col in the ps axu output
        System.cpu_usage(pid).to_f
      end
      
      def check(value)
        value < @below
      end
    end
  end
end