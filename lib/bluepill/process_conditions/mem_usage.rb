module Bluepill
  module ProcessConditions
    class MemUsage < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
      end
      
      def run(pid)
        # rss is on the 5th col
        System.ps_axu[pid][4].to_f
      end
      
      def check(value)
        value < @below
      end
    end
  end
end