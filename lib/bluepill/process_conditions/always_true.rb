module Bluepill
  module ProcessConditions
    class AlwaysTrue < ProcessCondition
      def initialize(options = {})
        super
        @below = options[:below]
      end

      def run(_pid, _include_children)
        1
      end

      def check(_value)
        true
      end
    end
  end
end
