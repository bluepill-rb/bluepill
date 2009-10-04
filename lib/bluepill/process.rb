require "state_machine"

module Bluepill
  class Process
    attr_accessor :name, :start_command, :stop_command, :restart_command, :daemonize, :pid_file

    state_machine :initial => :unmonitored do
      state :unmonitored, :up, :down
      
      event :tick do
        transition :unmonitored => :unmonitored
        
        transition [:up, :down] => :up, :if => :process_running?
        transition [:up, :down] => :down, :unless => :process_running?        
      end
      
      event :start do
        transition :unmonitored => :up, :if => lambda {|process| process.process_running? || process.start_process }
        transition :up => :up
        transition :down => :up, :if => :start_process
      end
      
      event :stop do
        transition [:unmonitored, :down] => :unmonitored
        transition :up => :unmonitored, :if => :stop_process
      end
      
      event :restart do
        transition all => :up, :if => :restart_process
      end
      
      event :unmonitor do
        transition all => :unmonitored
      end
      
    end

    def tick
      # clear the momoization per tick
      @process_running = nil

      # run state machine transitions
      super
      
      if process_running?
        run_watches
      end
    end
    
    def initialize(process_name, &block)
      raise ArgumentError, "Process needs to be constructed with a block" unless block_given?
      
      @name = process_name
      yield(self)
      
      raise ArgumentError, "Please specify a pid_file or the demonize option" if pid_file.nil? && !daemonize?
      super()
    end
    
    def daemonize?
      !!self.daemonize
    end
    
    def dispatch!(event)
      self.send("#{event}!")
    end
    
    # TODO. Must memoize result per tick
    def running?
      @process_running ||= signal_process(0)
    end
    
    # TODO
    def start_process
      
    end
    
    # TODO
    def stop_process
      
    end
    
    # TODO
    def restart_process
      
    end
    
    # TODO
    def run_watches
      
    end
    
    def signal_process(code)
      Process.kill(code, actual_pid)
      true
    rescue
      false
    end
    
    def actual_pid
      @actual_pid ||= File.read(pid_file).to_i
    end
  end
end
 