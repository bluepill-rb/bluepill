module BluePill
  module ProcessConditions
    class MemUsage < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
      end
      
      def run(pid)
        `ps ux -p #{pid} | tail -1 | awk '{print $5}'`.to_f
      end
      
      def check(value)
        value < @below
      end
    end
  end
end