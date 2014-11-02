module Bluepill
  module ProcessConditions
    class ProcessCondition
      def initialize(options = {})
        @options = options
      end

      def run(pid, include_children)
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
