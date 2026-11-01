module Bluepill
  module ProcessConditions
    class FileTime < ProcessCondition
      def initialize(options = {})
        super
        @below = options[:below]
        @filename = options[:filename]
      end

      def run(_pid, _include_children)
        Time.now - File.mtime(@filename) if File.exist?(@filename)
      rescue StandardError => e
        e
      end

      def check(value)
        value.is_a?(Numeric) && value < @below
      end
    end
  end
end
