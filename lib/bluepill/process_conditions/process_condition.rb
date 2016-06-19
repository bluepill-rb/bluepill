module Bluepill
  module ProcessConditions
    class ProcessCondition
      def initialize(options = {})
        @options = options
      end

      def run(_pid, _include_children)
        raise 'Implement in subclass!'
      end

      def check(_value)
        raise 'Implement in subclass!'
      end

      def format_value(value)
        value
      end
    end
  end
end
