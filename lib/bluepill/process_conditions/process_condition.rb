module Bluepill
  module ProcessConditions
    class ProcessCondition  
      def run(pid)
        raise "Implement in subclass!"
      end
      
      def check(value)
        raise "Implement in subclass!"
      end
      
      def format_value(value)
        value
      end
    end
  end
end