require "state_machine"
require "daemons"

module Bluepill
  class Process
    CONFIGURABLE_ATTRIBUTES = [:start_command, :stop_command, :restart_command, :daemonize, :pid_file, :start_grace_time, :stop_grace_time, :restart_grace_time]
    
    attr_accessor :name, :watches, :logger, :skip_ticks_until
    attr_accessor *CONFIGURABLE_ATTRIBUTES
    
    state_machine :initial => :unmonitored do      
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
        unless transition.loopback?
          process.record_transition(transition.from_name, transition.to_name)
        end
      end
      
    end

    def tick
      return if self.skip_ticks_until && self.skip_ticks_until > Time.now.to_i
      self.skip_ticks_until = nil

      # clear the momoization per tick
      @process_running = nil
      
      # run state machine transitions
      super

      
      if process_running?
        run_watches
      end
    end
    
    def initialize(process_name, options = {})      
      @name = process_name
      @transition_history = Util::RotationalArray.new(10)
      @watches = []
      
      @stop_grace_time = @start_grace_time = @restart_grace_time = 3
      
      CONFIGURABLE_ATTRIBUTES.each do |attribute_name|
        self.send("#{attribute_name}=", options[attribute_name]) if options.has_key?(attribute_name)
      end
      
      raise ArgumentError, "Please specify a pid_file or the demonize option" if pid_file.nil? && !daemonize?
      
      # Let state_machine do its initialization stuff
      super()
    end
    
    def add_watch(name, options = {})
      self.watches << ConditionWatch.new(name, options.merge(:logger => self.logger))
    end
    
    def daemonize?
      !!self.daemonize
    end
    
    def dispatch!(event)
      self.send("#{event}!")
    end
    
    def logger=(logger)
      @logger = logger
      self.watches.each {|w| w.logger = logger }
    end
    
    def process_running?(force = false)
      @process_running = nil if force
      @process_running ||= signal_process(0)
    end
    
    def start_process
      self.clear_pid
      if daemonize?
        starter = lambda {::Kernel.exec(start_command)}
        child_pid = Daemonize.call_as_daemon(starter)
        File.open(pid_file, "w") {|f| f.write(child_pid)}
        
      else
        # This is a self-daemonizing process
        system(start_command)
      end
      
      skip_ticks_for(start_grace_time)
      
      true
    end
    
    def stop_process
      self.clear_pid
      if stop_command
        system(stop_command)
      else
        signal_process("TERM")
        
        wait_until = Time.now.to_i + stop_grace_time
        while process_running?(true)
          if wait_until <= Time.now.to_i
            signal_process("KILL")
            break
          end
          sleep 0.1
        end
      end

      skip_ticks_for(stop_grace_time)
      
      true
    end
    
    def restart_process
      self.clear_pid
      if restart_command
        system(restart_command)
        skip_ticks_for(restart_grace_time)
        
      else
        stop_process
        start_process
      end
    end
    
    def skip_ticks_for(seconds)
      self.skip_ticks_until = (self.skip_ticks_until || Time.now.to_i) + seconds
    end

    def run_watches
      now = Time.now.to_i

      threads = self.watches.collect do |watch|
        [watch, Thread.new { Thread.current[:events] = watch.run(self.actual_pid, now) }]
      end
      
      @transitioned = false
      
      threads.inject([]) do |events, (watch, thread)|
        thread.join
        if thread[:events].size > 0
          logger.info "#{watch.name} dispatched: #{thread[:events].join(',')}"
          events << thread[:events]
        end
        events
      end.flatten.uniq.each do |event|
        break if @transitioned
        self.dispatch!(event)
      end
    end
    
    def record_transition(from, to)
      @transitioned = true
      logger.info "Going from #{from} => #{to}"
      self.watches.each { |w| w.clear_history! }
    end
    
    def signal_process(code)
      ::Process.kill(code, actual_pid)
      true
    rescue
      false
    end
    
    def actual_pid
      @actual_pid ||= File.read(pid_file).to_i if File.exists?(pid_file)
    end
    
    def clear_pid
      @actual_pid = nil
      File.unlink(pid_file) if File.exists?(pid_file)
    end
  end
end
 