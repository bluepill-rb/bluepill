require "state_machine"
require "daemons"

module Bluepill
  class Process
    attr_accessor :name, :start_command, :stop_command, :restart_command, :daemonize, :pid_file
    attr_accessor :watches, :logger, :skip_ticks_until
    
    state_machine :initial => :unmonitored do
      after_transition :down => :up do |process, transition|
        process.skip_ticks_until = Time.now.to_i + process.start_grace_time
      end
      
      state :unmonitored, :up, :down
      
      event :tick do
        transition :unmonitored => :unmonitored
        
        transition :up => :up, :if => :process_running?
        transition :up => :down, :unless => :process_running?

        transition :down => :up, :if => lambda {|process| process.process_running? || process.start_process }
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
      
      after_transition any => any do |process, transition|
        process.record_transition(transition.to_name) unless transition.loopback?
      end
      
    end

    def tick
      # clear the momoization per tick
      return if self.skip_ticks_until && self.skip_ticks_until > Time.now.to_i
      self.skip_ticks_until = nil
      
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
      @transition_history = Util::RotationalArray.new(10)
      yield(self)
      
      @watch_logger = Logger.new(self.logger, "#{self.name}:") if self.logger
      self.watches = []
      
      raise ArgumentError, "Please specify a pid_file or the demonize option" if pid_file.nil? && !daemonize?
      super()
    end
    
    def add_watch(name, options = {})
      self.watches << ConditionWatch.new(name, options.merge(:logger => @watch_logger))
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
        @process_running
      else
        @process_running
      end
    end
    
    def start_process
      puts "STARTING"
      @actual_pid = nil
      if daemonize?
        if fork.nil?
          Daemonize.daemonize
          File.open(pid_file, "w") {|f| f.write(::Process.pid)}
          exec(start_command)
        end
      else
        # This is a self-daemonizing process
        system(start_command)
      end
      
      true
    end
    
    def stop_process
      @actual_pid = nil
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
      @actual_pid = nil
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
    def start_grace_time
      3
    end

    def run_watches
      now = Time.now.to_i
      
      threads = self.watches.collect do |watch|
        Thread.new { Thread.current[:events] = watch.run(actual_pid, now) }
      end
      
      @transitioned = false
      
      threads.inject([]) do |events, thread|
        thread.join
        events << thread[:events]
      end.flatten.uniq.each do |event|
        break if @transitioned
        self.dispatch!(event)
      end
    end
    
    def record_transition(state_name)
      @transitioned = true
      # do other stuff here?
    end
    
    def signal_process(code)
      ::Process.kill(code, actual_pid)
      true
    rescue
      false
    end
    
    def actual_pid
      @actual_pid ||= File.read(pid_file).to_i
    end
  end
end
 