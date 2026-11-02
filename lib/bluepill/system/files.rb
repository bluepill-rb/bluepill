# frozen_string_literal: true

module Bluepill
  module System
    # Delete the files that bluepill leaves behind
    #
    # System extends this module, so these are System's module functions.
    #
    # @api private
    module Files
      # Delete a file if it exists
      #
      # It tries three times when permission is denied, and then prints a
      # warning instead of raising.
      #
      # @param [String, nil] filename the file's path
      #
      # @return [void]
      #
      # @api private
      def delete_if_exists(filename)
        tries = 0

        begin
          File.unlink(filename) if filename && File.exist?(filename)
        rescue IOError, Errno::ENOENT
          # Already gone, or another process removed it in between
        rescue Errno::EACCES
          retry if (tries += 1) < 3
          $stderr.puts("Warning: permission denied trying to delete #{filename}")
        end
      end
    end
  end
end
