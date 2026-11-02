# frozen_string_literal: true

module Bluepill
  module ProcessConditions
    # Checks whether a process is a zombie, which ps shows as <defunct>
    #
    # A config names it `checks :zombie_process`. The process must have
    # cache_actual_pid set to false for it to work correctly.
    #
    # @example
    #   process.checks :zombie_process, every: 5.seconds
    #   process.cache_actual_pid = false
    #
    # @api private
    class ZombieProcess < ProcessCondition
      # Read the process's command line from the tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] _include_children whether to include its children
      #
      # @return [String, nil] the command line, or nil for a process ps
      #   doesn't list
      #
      # @api private
      def run(pid, _include_children)
        System.command(pid)
      end

      # Return whether the process isn't a zombie
      #
      # @param [String, nil] value the command line run read
      #
      # @return [Boolean] true unless the command line says <defunct>
      #
      # @api private
      def check?(value)
        !value&.match?(/<defunct>/)
      end
    end
  end
end
