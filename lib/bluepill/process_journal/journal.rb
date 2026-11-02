# frozen_string_literal: true

module Bluepill
  module ProcessJournal
    # A process's journals: its pid journal and its process group journal
    #
    # ProcessJournal.for makes one.
    #
    # @api private
    class Journal
      # Return the process's name
      #
      # @return [#to_s]
      #
      # @api private
      attr_reader :name

      # Make the journals of a process
      #
      # @param [#to_s] name the process's name
      #
      # @return [void]
      #
      # @api private
      def initialize(name) = @name = name

      # Add a pid, and its process group id, to the journals
      #
      # An invalid pid, nil or 1 or less, is skipped.
      #
      # @param [Integer, nil] pid the pid
      #
      # @return [void]
      #
      # @api private
      def append(pid)
        ProcessJournal.append(PID, name, pid) { |valid_pid| append_process_group(valid_pid) }
      end

      # Kill the processes, and then the process groups, the journals list
      #
      # That's the app's journals, and the ones that bluepill 0.1 and earlier
      # shared between apps.
      #
      # @return [void]
      #
      # @api private
      def kill_all
        ProcessJournal.kill_all(PID, name)
        ProcessJournal.kill_all(PGID, name)
      end

      private

      # Add a process's process group id to the process group journal
      #
      # @param [Integer] pid the process's pid
      #
      # @return [void]
      #
      # @api private
      def append_process_group(pid)
        ProcessJournal.append(PGID, name, ::Process.getpgid(pid))
      rescue Errno::ESRCH
        # The process is gone, so it has no process group to journal
      end
    end
  end
end
