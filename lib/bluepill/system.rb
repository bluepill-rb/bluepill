module Bluepill
  # Read what the system says about its processes, and run commands
  #
  # This represents the system that bluepill is running on. It memoizes
  # the results of running ps each tick, so that every watch of every
  # process doesn't fork a ps of its own.
  #
  # @api private
  module System
    # The mode that a daemon's stdout and stderr files are opened in
    #
    # @api private
    APPEND_MODE = 'a'.freeze

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
      command: 5,
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
    rescue StandardError
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
      elapsed = IO.popen(['ps', '-o', 'etime=', '-p', Integer(pid).to_s], err: File::NULL, &:read).rstrip
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

    # Return the pids in this tick's ps table by their parent's pid
    #
    # It's built once per ps table, so finding a process's descendants
    # takes as long as there are descendants, not a pass over the whole
    # table for each one.
    #
    # @return [Hash{Integer => Array<Integer>}] each parent's children, in
    #   ps's order
    #
    # @raise [PsError] if ps could not be run
    #
    # @api private
    def self.children_by_parent
      @children_by_parent ||= begin
        index = {} #: Hash[Integer, Array[Integer]]
        ps_axu.each_pair { |pid, chunks| (index[chunks.fetch(IDX_MAP.fetch(:ppid)).to_i] ||= []) << pid }
        index
      end
    end

    # Return the pids of a process's descendants, from this tick's ps table
    #
    # @param [Integer, nil] parent_pid the process's pid
    #
    # @return [Array<Integer>] its children's pids, followed by theirs, or
    #   none if ps could not be run
    #
    # @api private
    def self.get_children(parent_pid)
      # A process that is still starting has no pid yet, and nil.to_i is 0.
      # The ps header row parses as pid 0 with ppid 0, so it would be its own
      # child and the recursion would never end.
      return NO_PIDS unless parent_pid.to_i > 0

      # Most processes have no children, and they all share one empty array
      children = children_by_parent.fetch(parent_pid) { return NO_PIDS }
      descendants = children.dup
      children.each { |pid| descendants.concat(get_children(pid)) }
      descendants
    rescue PsError
      NO_PIDS
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

    # Return what this tick has memoized
    #
    # @return [Hash{Symbol => Hash{Integer => Array<String>}, String}] the
    #   ps table, or ps's error, by name
    #
    # @api private
    def self.store
      @store ||= {}
    end

    # Forget what the last tick memoized, so ps runs again
    #
    # @return [void]
    #
    # @api private
    def self.reset_data
      @children_by_parent = nil
      store.clear
    end

    # Watches run in their own threads, so only let one of them run ps per tick
    #
    # @api private
    PS_MUTEX = Mutex.new

    # No pids, which get_children returns for a process with no children
    no_pids = [] #: Array[Integer]
    NO_PIDS = no_pids.freeze

    # Return this tick's ps table, running ps the first time it's asked for
    #
    # @return [Hash{Integer => Array<String>}] each process's ps fields, by
    #   pid, in the order of IDX_MAP
    #
    # @raise [PsError] if ps could not be run this tick
    #
    # @api private
    def self.ps_axu
      ps = PS_MUTEX.synchronize do
        store[:ps_axu] ||= begin
          # POSIX options, so this also works with System V ps on Solaris and SmartOS.
          # Use -A because -e shows the environment on FreeBSD and OpenBSD.
          lines = `ps -Ao pid,ppid,pcpu,rss,etime,args`.split("\n")

          table = {} #: ps_table
          lines.each do |line|
            chunks = line.split
            pid = chunks.fetch(IDX_MAP.fetch(:pid)).to_i
            command = chunks.slice!(IDX_MAP.fetch(:command), chunks.length) #: Array[String]
            chunks[IDX_MAP.fetch(:command)] = command.join ' '
            table[pid] = chunks
          end
          table
        rescue SystemCallError => e
          # Forking ps can fail, for example with ENOMEM or EAGAIN under memory pressure.
          # Cache the message so ps is not run again until the next tick.
          "Could not run ps: #{e.class}: #{e}"
        end
      end
      raise PsError, ps if ps.instance_of?(String)

      ps
    end

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

require 'bluepill/system/commands'
