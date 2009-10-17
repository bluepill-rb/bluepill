module Bluepill
  module ProcessConditions
    class MemUsage < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
      end
      
      def run(pid)
        # rss is on the 5th col
        System.memory_usage(pid).to_f
      end
      
      def check(value)
        value < @below
      end
    end
  end
end