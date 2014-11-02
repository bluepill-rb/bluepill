module Bluepill
  module ProcessConditions
    class AlwaysTrue < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
      end

      def run(pid, include_children)
        1
      end

      def check(value)
        true
      end
    end
  end
end
