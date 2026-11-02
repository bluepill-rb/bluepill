module Bluepill
  module ProcessConditions
    # Checks how long ago a file changed, in seconds
    #
    # A config names it `checks :file_time`, with filename: the file, and
    # below: the longest it may go without changing (3.minutes, say), to
    # restart a process that stopped writing its log or heartbeat file.
    #
    # @example
    #   process.checks :file_time, every: 60.seconds, below: 3.minutes, filename: "/tmp/some_file.log", times: 2
    #
    # @api private
    class FileTime < ProcessCondition
      # Create the check
      #
      # @param [Hash{Symbol => Object}] options the check's options, with
      #   :filename, the file, and :below, the longest it may go without
      #   changing, in seconds
      #
      # @return [void]
      #
      # @api private
      def initialize(options = {})
        super
        @below = options[:below]
        @filename = options[:filename]
      end

      # Read the seconds since the file changed
      #
      # @param [Integer, nil] _pid the process's pid
      # @param [Boolean] _include_children whether to include its children
      #
      # @return [Float, StandardError, nil] the seconds, nil when the file
      #   doesn't exist, or the error that stopped bluepill from finding out
      #
      # @api private
      def run(_pid, _include_children)
        Time.now - File.mtime(@filename) if File.exist?(@filename)
      rescue => e
        e
      end

      # Return whether the file changed recently enough
      #
      # @param [Float, StandardError, nil] value what run read
      #
      # @return [Boolean] true when the seconds are below the limit, false
      #   for a missing file or an error
      #
      # @api private
      def check?(value)
        value.is_a?(Numeric) && value < @below
      end
    end
  end
end
