# frozen_string_literal: true

module Bluepill
  module System
    # What a command that ran until it finished printed, and how it exited
    #
    # @api private
    class CommandResult
      # Make a result from the Hash that the command's child reports
      #
      # @param [Hash{Symbol => Object}] result its :exit_code, :stdout and
      #   :stderr
      #
      # @return [CommandResult]
      #
      # @api private
      def self.from_h(result)
        new(exit_code: result.fetch(:exit_code), stdout: result.fetch(:stdout), stderr: result.fetch(:stderr))
      end

      # Return the command's exit status
      #
      # @return [Integer, nil] the status, or nil if a signal ended it
      #
      # @api private
      attr_reader :exit_code

      # Return what the command printed to its standard output
      #
      # @return [String]
      #
      # @api private
      attr_reader :stdout

      # Return what the command printed to its standard error
      #
      # @return [String]
      #
      # @api private
      attr_reader :stderr

      # Describe a command's result
      #
      # @param [Integer, nil] exit_code the exit status, or nil if a signal
      #   ended the command
      # @param [String] stdout what it printed to its standard output
      # @param [String] stderr what it printed to its standard error
      #
      # @return [void]
      #
      # @api private
      def initialize(exit_code:, stdout: "", stderr: "")
        @exit_code = exit_code
        @stdout = stdout
        @stderr = stderr
      end

      # Return whether the command exited with status 0
      #
      # @return [Boolean]
      #
      # @api private
      def success? = exit_code&.zero? || false

      # Return the result as a Hash, as the command's child reports it
      #
      # @return [Hash{Symbol => Object}] the :exit_code, :stdout and :stderr
      #
      # @api private
      def to_h = {exit_code:, stdout:, stderr:}
    end
  end
end
