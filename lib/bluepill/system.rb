module Bluepill
  # This class represents the system that bluepill is running on.. It's mainly used to memoize
  # results of running ps auxx etc so that every watch in the every process will not result in a fork
  module System
    extend self
    
    # The position of each field in ps output
    IDX_MAP = {
      :pid => 0,
      :ppid => 1,
      :pcpu => 2,
      :rss => 3
    }
    
    def cpu_usage(pid)
      ps_axu[pid] && ps_axu[pid][IDX_MAP[:pcpu]].to_f
    end
    
    def memory_usage(pid)
      ps_axu[pid] && ps_axu[pid][IDX_MAP[:rss]].to_f
    end
    
    def get_children(parent_pid)
      returning(Array.new) do |child_pids|
        ps_axu.each_pair do |pid, chunks| 
          child_pids << chunks[IDX_MAP[:pid]].to_i if chunks[IDX_MAP[:ppid]].to_i == parent_pid.to_i
        end
      end
    end
    
    def execute_non_blocking(cmd)
      if Daemonize.safefork
        # In parent, return immediately
        return
        
      else
        # in child
        ::Kernel.exec(cmd)
        # execution should not reach here
        exit
      end
    end
    
    def store
      @store ||= Hash.new
    end
    
    def reset_data
      store.clear unless store.empty?
    end
    
    def ps_axu
      store[:ps_axu] ||= begin
        # BSD style ps invocation
        lines = `ps axo pid=,ppid=,pcpu=,rss=`.split("\n")

        lines.inject(Hash.new) do |mem, line| 
          chunks = line.split(/\s+/)
          chunks.delete_if {|c| c.strip.empty? }
          pid = chunks[IDX_MAP[:pid]].strip.to_i
          mem[pid] = chunks
          mem
        end
      end
    end
  end
end