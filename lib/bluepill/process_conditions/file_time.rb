module Bluepill
  module ProcessConditions
    class FileTime < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
        @filename = options[:filename]
      end

      def run(_pid, _include_children)
        if File.exist?(@filename)
          Time.now - File.mtime(@filename)
        else
          nil
        end
      rescue
        $ERROR_INFO
      end

      def check(value)
        return false if value.nil?
        value < @below
      end
    end
  end
end
