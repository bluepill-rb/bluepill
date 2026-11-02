require "bluepill/system/ps"
require "bluepill/system/commands"

module Bluepill
  # Read what the system says about its processes, and run commands
  #
  # This represents the system that bluepill is running on. It memoizes
  # the results of running ps each tick, so that every watch of every
  # process doesn't fork a ps of its own. Running ps and reading its table
  # is in System::Ps, and running commands is in System::Commands and
  # System::Daemon. System extends them all.
  #
  # @api private
  module System
    extend Ps
    extend Commands
    extend Daemon

    # The mode that a daemon's stdout and stderr files are opened in
    #
    # @api private
    APPEND_MODE = "a".freeze

    # Raised when ps could not be run, so there is no data for this tick
    #
    # @api private
    class PsError < StandardError; end

    # The position of each field in ps output
    #
    # @api private
    IDX_MAP = {
      pid: 0,
      ppid: 1,
      pcpu: 2,
      rss: 3,
      etime: 4,
      command: 5
    }.freeze #: { pid: Integer, ppid: Integer, pcpu: Integer, rss: Integer, etime: Integer, command: Integer }

    # Return whether a process is running
    #
    # @param [Integer] pid the process's pid
    #
    # @return [Boolean] true if the process exists, even if bluepill may
    #   not signal it
    #
    # @api private
    def self.pid_alive?(pid)
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
    def self.started_at(pid)
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
    def self.boot_time
      started_at(1)
    end

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
    def self.cpu_usage(pid, include_children)
      ps = ps_axu
      return unless ps.key?(pid)

      cpu_used = ps.fetch(pid).fetch(IDX_MAP.fetch(:pcpu)).to_f
      if include_children
        get_children(pid).each do |child_pid|
          cpu_used += ps.fetch(child_pid).fetch(IDX_MAP.fetch(:pcpu)).to_f if ps.key?(child_pid)
        end
      end
      cpu_used
    end

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
    def self.memory_usage(pid, include_children)
      ps = ps_axu
      return unless ps.key?(pid)

      mem_used = ps.fetch(pid).fetch(IDX_MAP.fetch(:rss)).to_f
      if include_children
        get_children(pid).each do |child_pid|
          mem_used += ps.fetch(child_pid).fetch(IDX_MAP.fetch(:rss)).to_f if ps.key?(child_pid)
        end
      end
      mem_used
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
    def self.running_time(pid)
      ps = ps_axu
      return unless ps.key?(pid)

      parse_elapsed_time(ps.fetch(pid).fetch(IDX_MAP.fetch(:etime)))
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
    def self.command(pid)
      ps = ps_axu
      return unless ps.key?(pid)

      ps.fetch(pid).fetch(IDX_MAP.fetch(:command))
    end

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
    def self.delete_if_exists(filename)
      tries = 0

      begin
        File.unlink(filename) if filename && File.exist?(filename)
      rescue IOError, Errno::ENOENT
      rescue Errno::EACCES
        retry if (tries += 1) < 3
        $stderr.puts("Warning: permission denied trying to delete #{filename}")
      end
    end

    # Watches run in their own threads, so only let one of them run ps per tick
    #
    # @api private
    PS_MUTEX = Mutex.new

    # No pids, which get_children returns for a process with no children
    no_pids = [] #: Array[Integer]
    NO_PIDS = no_pids.freeze

    # Convert ps's elapsed time to seconds
    #
    # @param [String, nil] str an elapsed time, [[dd-]hh:]mm:ss
    #
    # @return [Integer] the seconds, or 0 if str isn't an elapsed time
    #
    # @api private
    def self.parse_elapsed_time(str)
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
