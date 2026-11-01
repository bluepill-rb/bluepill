module Bluepill
  # This class represents the system that bluepill is running on.. It's mainly used to memoize
  # results of running ps auxx etc so that every watch in the every process will not result in a fork
  module System
    APPEND_MODE = 'a'.freeze

    # Raised when ps could not be run, so there is no data for this tick
    class PsError < StandardError; end

  module_function

    # The position of each field in ps output
    IDX_MAP = {
      pid: 0,
      ppid: 1,
      pcpu: 2,
      rss: 3,
      etime: 4,
      command: 5,
    }.freeze

    def pid_alive?(pid)
      ::Process.kill(0, pid)
      true
    rescue Errno::EPERM # no permission, but it is definitely alive
      true
    rescue Errno::ESRCH
      false
    rescue StandardError
      false # other falsy (no pid)
    end

    def cpu_usage(pid, include_children)
      ps = ps_axu
      return unless ps[pid]

      cpu_used = ps[pid][IDX_MAP[:pcpu]].to_f
      if include_children
        get_children(pid).each do |child_pid|
          cpu_used += ps[child_pid][IDX_MAP[:pcpu]].to_f if ps[child_pid]
        end
      end
      cpu_used
    end

    def memory_usage(pid, include_children)
      ps = ps_axu
      return unless ps[pid]

      mem_used = ps[pid][IDX_MAP[:rss]].to_f
      if include_children
        get_children(pid).each do |child_pid|
          mem_used += ps[child_pid][IDX_MAP[:rss]].to_f if ps[child_pid]
        end
      end
      mem_used
    end

    def running_time(pid)
      ps = ps_axu
      return unless ps[pid]

      parse_elapsed_time(ps[pid][IDX_MAP[:etime]])
    end

    def command(pid)
      ps = ps_axu
      return unless ps[pid]

      ps[pid][IDX_MAP[:command]]
    end

    def get_children(parent_pid)
      child_pids = []
      ps_axu.each_pair do |_pid, chunks|
        child_pids << chunks[IDX_MAP[:pid]].to_i if chunks[IDX_MAP[:ppid]].to_i == parent_pid.to_i
      end
      grand_children = child_pids.collect { |pid| get_children(pid) }.flatten
      child_pids.concat grand_children
    rescue PsError
      []
    end

    def delete_if_exists(filename)
      tries = 0

      begin
        File.unlink(filename) if filename && File.exist?(filename)
      rescue IOError, Errno::ENOENT
      rescue Errno::EACCES
        retry if (tries += 1) < 3
        $stderr.puts("Warning: permission denied trying to delete #{filename}")
      end
    end

    def store
      @store ||= {}
    end

    def reset_data
      store.clear unless store.empty?
    end

    # Watches run in their own threads, so only let one of them run ps per tick
    PS_MUTEX = Mutex.new

    def ps_axu
      ps = PS_MUTEX.synchronize do
        store[:ps_axu] ||= begin
          # POSIX options, so this also works with System V ps on Solaris and SmartOS.
          # Use -A because -e shows the environment on FreeBSD and OpenBSD.
          lines = `ps -Ao pid,ppid,pcpu,rss,etime,args`.split("\n")

          lines.each_with_object({}) do |line, mem|
            chunks = line.split(/\s+/)
            chunks.delete_if { |c| c.strip.empty? }
            pid = chunks[IDX_MAP[:pid]].strip.to_i
            command = chunks.slice!(IDX_MAP[:command], chunks.length).join ' '
            chunks[IDX_MAP[:command]] = command
            mem[pid] = chunks.flatten
          end
        rescue SystemCallError => e
          # Forking ps can fail, for example with ENOMEM or EAGAIN under memory pressure.
          # Cache the message so ps is not run again until the next tick.
          "Could not run ps: #{e.class}: #{e.message}"
        end
      end
      raise PsError, ps if ps.is_a?(String)

      ps
    end

    def parse_elapsed_time(str)
      # [[dd-]hh:]mm:ss
      if str =~ /(?:(?:(\d+)-)?(\d\d):)?(\d\d):(\d\d)/
        days = (Regexp.last_match[1] || 0).to_i
        hours = (Regexp.last_match[2] || 0).to_i
        mins = Regexp.last_match[3].to_i
        secs = Regexp.last_match[4].to_i
        ((days * 24 + hours) * 60 + mins) * 60 + secs
      else
        0
      end
    end
  end
end

require 'bluepill/system/commands'
