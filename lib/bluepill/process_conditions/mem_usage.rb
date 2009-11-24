module Bluepill
  module ProcessConditions
    class MemUsage < ProcessCondition
      MB = 1024 ** 2
      FORMAT_STR = "%d%s"
      MB_LABEL = "MB"
      KB_LABEL = "KB"
      
      def initialize(options = {})
        @below = options[:below]
      end
      
      def run(pid)
        # rss is on the 5th col
        System.memory_usage(pid).to_f
      end
      
      def check(value)
        value.kilobytes < @below
      end
      
      def format_value(value)
        if value.kilobytes >= MB
          FORMAT_STR % [(value / 1024).round, MB_LABEL]
        else
          FORMAT_STR % [value, KB_LABEL]
        end
      end
    end
  end
end