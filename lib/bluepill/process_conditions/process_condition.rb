module BluePill
  module ProcessConditions
    class ProcessCondition  
      def run(pid)
        raise "Implement in subclass!"
      end
      
      def check(value)
        raise "Implement in subclass!"
      end
    end
  end
end