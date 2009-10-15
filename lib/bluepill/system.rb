require "singleton"
module Bluepill
  # This class represents the system that bluepill is running on.. It's mainly used to memoize
  # results of running ps auxx etc so that every watch in the every process will not result in a fork
  module System
    extend self
    
    def store
      @store ||= Hash.new
    end
    
    def reset_data
      store.clear unless store.empty?
    end
    
    def ps_axu
      store[:ps_axu] ||= begin
        # BSD style ps invocation
        lines = `ps axu`.split("\n")
        
        lines.inject(Hash.new) do |mem, line| 
          # There are 11 cols in the ps ax output. This keeps programs that use spaces in $0 in one chunk
          chunks = line.split(/\s+/, 11)
          pid = chunks[1].to_i
          mem[pid] = chunks
          
          mem
        end
      end
    end
  end
end