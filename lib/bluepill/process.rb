require "state_machine"
require "daemons"

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
    
    def process_running?(force = false)
      if force || @process_running.nil?
        @process_running = signal_process(0)
      else
        @process_running
      end
    end
    
    def start_process
      if daemonize?
        Daemons.call do
          File.open(pid_file, "w") {|f| f.write(Process.pid)}
          exec(start_command)
        end
        
      else
        # This is a self-daemonizing process
        system(start_command)
      end
      
      true
    end
    
    def stop_process
      if stop_command
        system(stop_command)
        
      else
        signal_process("TERM")
        sleep(stop_grace_time)
        signal_process("KILL") if process_running?(true)
      end
      
      true
    end
    
    def restart_process
      if restart_command
        system(restart_command)
        
      else
        stop_process
        sleep(restart_grace_time)
        start_process
      end
    end
    
    # TODO
    def stop_grace_time
      3
    end
    
    # TODO
    def restart_grace_time
      3
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
 