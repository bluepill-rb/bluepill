# -*- encoding: utf-8 -*-
module Bluepill
  module ProcessConditions
    class FileTime < ProcessCondition
      def initialize(options = {})
        @below = options[:below]
        @filename = options[:filename]
      end

      def run(pid, include_children)
        if File.exists?(@filename)
          Time.now()-File::mtime(@filename)
        else
          nil
        end
      rescue
        $!
      end

      def check(value)
        return false if value.nil?
        return value < @below
      end
    end
  end
end
