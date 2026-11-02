# frozen_string_literal: true

module Bluepill
  module System
    # Ask the system about a process: whether it's alive, when it started,
    # and what this tick's ps table says it uses
    #
    # System extends this module, so these are System's module functions.
    #
    # @api private
    module Usage
      # Return whether a process is running
      #
      # @param [Integer] pid the process's pid
      #
      # @return [Boolean] true if the process exists, even if bluepill may
      #   not signal it
      #
      # @api private
      def pid_alive?(pid)
        ::Process.kill(0, pid)
        true
      rescue Errno::EPERM # no permission, but it is definitely alive
        true
      rescue
        false # no such process (ESRCH), or no pid
      end

      # Return when a process started, in seconds since the epoch
      #
      # It's read from ps's elapsed time for the process, so it's accurate to
      # about a second, and works wherever ps does.
      #
      # @param [Integer] pid the process's pid
      #
      # @return [Integer, nil] when it started, or nil if there's no such
      #   process
      #
      # @api private
      def started_at(pid)
        # ps says why on stderr when there's no such process
        elapsed = IO.popen(["ps", "-o", "etime=", "-p", Integer(pid).to_s], err: File::NULL, &:read).rstrip
        Integer(Time.now) - parse_elapsed_time(elapsed) unless elapsed.empty?
      rescue SystemCallError
        nil
      end

      # Return when the machine booted, in seconds since the epoch
      #
      # That's when its first process, pid 1, started. In a container, it's
      # when the container started, which is when its pids start over.
      #
      # @return [Integer, nil] when it booted, or nil if ps can't tell
      #
      # @api private
      def boot_time = started_at(1)

      # Return a process's CPU usage, from this tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] include_children whether to add its descendants'
      #
      # @return [Float, nil] the percent of a CPU it uses, or nil if ps doesn't
      #   list it
      #
      # @raise [PsError] if ps could not be run this tick
      #
      # @api private
      def cpu_usage(pid, include_children) = usage(pid, include_children, PsTable::PCPU)

      # Return a process's resident memory, from this tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] include_children whether to add its descendants'
      #
      # @return [Float, nil] its resident memory in kilobytes, or nil if ps
      #   doesn't list it
      #
      # @raise [PsError] if ps could not be run this tick
      #
      # @api private
      def memory_usage(pid, include_children) = usage(pid, include_children, PsTable::RSS)

      # Return a column of a process's row, from this tick's ps table, as a Float
      #
      # @param [Integer, nil] pid the process's pid
      # @param [Boolean] include_children whether to add its descendants'
      # @param [Integer] column the column, PsTable::PCPU or PsTable::RSS
      #
      # @return [Float, nil] the process's value, and its descendants' if
      #   asked for, or nil if ps doesn't list it
      #
      # @raise [PsError] if ps could not be run this tick
      #
      # @api private
      def usage(pid, include_children, column)
        ps = ps_axu
        row = ps.row(pid)
        return unless row

        used = row.fetch(column).to_f
        include_children ? ps.sum(get_children(pid), column, used) : used
      end

      # Return how long a process has been running, from this tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      #
      # @return [Integer, nil] its running time in seconds, or nil if ps
      #   doesn't list it
      #
      # @raise [PsError] if ps could not be run this tick
      #
      # @api private
      def running_time(pid)
        row = ps_axu.row(pid)
        parse_elapsed_time(row.fetch(PsTable::ETIME)) if row
      end

      # Return a process's command line, from this tick's ps table
      #
      # @param [Integer, nil] pid the process's pid
      #
      # @return [String, nil] its command and arguments, or nil if ps doesn't
      #   list it
      #
      # @raise [PsError] if ps could not be run this tick
      #
      # @api private
      def command(pid)
        row = ps_axu.row(pid)
        row&.fetch(PsTable::COMMAND)
      end

      # Convert ps's elapsed time to seconds
      #
      # @param [String, nil] str an elapsed time, [[dd-]hh:]mm:ss
      #
      # @return [Integer] the seconds, or 0 if str isn't an elapsed time
      #
      # @api private
      def parse_elapsed_time(str)
        # [[dd-]hh:]mm:ss
        match = /(?:(?:(\d+)-)?(\d\d):)?(\d\d):(\d\d)/.match(str)
        if match
          hours = (match[1].to_i * 24) + match[2].to_i
          mins = (hours * 60) + match[3].to_i
          (mins * 60) + match[4].to_i
        else
          0
        end
      end
    end
  end
end
