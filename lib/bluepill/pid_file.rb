# frozen_string_literal: true

module Bluepill
  # Read the pid file of a bluepill daemon
  #
  # @api private
  module PidFile
    # Return the pid in a pid file
    #
    # An empty or garbled pid file reads as 0, which is no pid, since
    # signaling pid 0 would signal the reader's own process group.
    #
    # @param [String] path the pid file
    #
    # @return [Integer, nil] the pid, or nil without the file or a pid in it
    #
    # @api private
    def self.read(path)
      return unless File.exist?(path)

      pid = File.read(path).to_i
      pid if pid > 0
    end
  end
end
