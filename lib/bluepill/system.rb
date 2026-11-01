module Bluepill
  # This class represents the system that bluepill is running on.. It's mainly used to memoize
  # results of running ps auxx etc so that every watch in the every process will not result in a fork
  module System
    APPEND_MODE = 'a'.freeze

    # Raised when ps could not be run, so there is no data for this tick
    class PsError < StandardError; end

    # The position of each field in ps output
    IDX_MAP = {
      pid: 0,
      ppid: 1,
      pcpu: 2,
      rss: 3,
      etime: 4,
      command: 5,
    }.freeze #: { pid: Integer, ppid: Integer, pcpu: Integer, rss: Integer, etime: Integer, command: Integer }

    def self.pid_alive?(pid)
      ::Process.kill(0, pid)
      true
    rescue Errno::EPERM # no permission, but it is definitely alive
      true
    rescue StandardError
      false # no such process (ESRCH), or no pid
    end

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

    def self.running_time(pid)
      ps = ps_axu
      return unless ps.key?(pid)

      parse_elapsed_time(ps.fetch(pid).fetch(IDX_MAP.fetch(:etime)))
    end

    def self.command(pid)
      ps = ps_axu
      return unless ps.key?(pid)

      ps.fetch(pid).fetch(IDX_MAP.fetch(:command))
    end

    def self.get_children(parent_pid)
      # A process that is still starting has no pid yet, and nil.to_i is 0.
      # The ps header row parses as pid 0 with ppid 0, so it would be its own
      # child and the recursion would never end.
      return [] unless parent_pid.to_i > 0

      child_pids = [] #: Array[Integer]
      ps_axu.each_pair do |_pid, chunks|
        child_pids << Integer(chunks.fetch(IDX_MAP.fetch(:pid))) if chunks.fetch(IDX_MAP.fetch(:ppid)).to_i.eql?(parent_pid)
      end
      grand_children = child_pids.collect { |pid| get_children(pid) }.flatten
      child_pids.concat grand_children
    rescue PsError
      []
    end

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

    def self.store
      @store ||= {}
    end

    def self.reset_data
      store.clear
    end

    # Watches run in their own threads, so only let one of them run ps per tick
    PS_MUTEX = Mutex.new

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

    def self.parse_elapsed_time(str)
      # [[dd-]hh:]mm:ss
      match = /(?:(?:(\d+)-)?(\d\d):)?(\d\d):(\d\d)/.match(str)
      if match
        days = match[1].to_i
        hours = match[2].to_i
        mins = match[3].to_i
        secs = match[4].to_i
        ((days * 24 + hours) * 60 + mins) * 60 + secs
      else
        0
      end
    end
  end
end

require 'bluepill/system/commands'
