require "state_machine"
require "daemons"

module Bluepill
  class Process
    CONFIGURABLE_ATTRIBUTES = [
      :start_command, 
      :stop_command, 
      :restart_command, 
      
      :daemonize, 
      :pid_file, 
      
      :start_grace_time, 
      :stop_grace_time, 
      :restart_grace_time,
      
      :uid,
      :gid,
      
      :monitor_children,
      :child_process_template
    ]
    
    attr_accessor :name, :watches, :triggers, :logger, :skip_ticks_until
    attr_accessor *CONFIGURABLE_ATTRIBUTES
    attr_reader :children
    
    state_machine :initial => :unmonitored do
      state :unmonitored, :up, :down, :restarting
      
      event :tick do
        transition :unmonitored => :unmonitored
        
        transition :up => :up, :if => :process_running?
        transition :up => :down, :unless => :process_running?

        transition :down => :up, :if => lambda {|process| process.process_running? || process.start_process }
        
        transition :restarting => :up, :if => :process_running?
        transition :restarting => :down, :unless => :process_running?
      end
      
      event :start do
        transition :unmonitored => :up, :if => lambda {|process| process.process_running? || process.start_process }
        transition [:restarting, :up] => :up
        transition :down => :up, :if => :start_process
      end
      
      event :stop do
        transition [:unmonitored, :down] => :unmonitored
        transition [:up, :restarting] => :unmonitored, :if => :stop_process
      end
      
      event :restart do
        transition all => :restarting, :if => :restart_process
      end
      
      event :unmonitor do
        transition all => :unmonitored
      end
      
      after_transition any => any do |process, transition|
        process.notify_triggers(transition)
        
        unless transition.loopback?
          process.record_transition(transition.from_name, transition.to_name)
          
          # When a process changes state, we should clear the memory of all the watches
          process.watches.each { |w| w.clear_history! }

          # Also, when a process changes state, we should re-populate its child list
          if process.monitor_children?
            process.logger.warning "Clearing child list"
            process.children.clear
          end
        end
      end
    end
    
    def initialize(process_name, options = {})      
      @name = process_name
      @event_mutex = Monitor.new
      @transition_history = Util::RotationalArray.new(10)
      @watches = []
      @triggers = []
      @children = []
      
      @monitor_children = options[:monitor_children] || false
      
      %w(start_grace_time stop_grace_time restart_grace_time).each do |grace|
        instance_variable_set("@#{grace}", options[grace.to_sym] || 3)
      end
      
      CONFIGURABLE_ATTRIBUTES.each do |attribute_name|
        self.send("#{attribute_name}=", options[attribute_name]) if options.has_key?(attribute_name)
      end
      
      # Let state_machine do its initialization stuff
      super()
    end

    def tick
      return if self.skipping_ticks?
      self.skip_ticks_until = nil

      # clear the memoization per tick
      @process_running = nil

      # run state machine transitions
      super

      if process_running?
        run_watches
        
        if monitor_children?
          refresh_children!
          children.each {|child| child.tick}
        end
      end
    end
    
    def logger=(logger)
      @logger = logger
      self.watches.each {|w| w.logger = logger }
      self.triggers.each {|t| t.logger = logger }
    end
    
    # State machine methods
    def dispatch!(event)
      @event_mutex.synchronize do
        self.send("#{event}!")
      end
    end
    
    def record_transition(from, to)
      @transitioned = true
      logger.info "Going from #{from} => #{to}"
    end
    
    def notify_triggers(transition)
      self.triggers.each {|trigger| trigger.notify(transition)}
    end

    
    # Watch related methods
    def add_watch(name, options = {})
      self.watches << ConditionWatch.new(name, options.merge(:logger => self.logger))
    end
    
    def add_trigger(name, options = {})
      self.triggers << Trigger[name].new(self, options.merge(:logger => self.logger))
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
    
    
    # System Process Methods
    def process_running?(force = false)
      @process_running = nil if force
      @process_running ||= signal_process(0)
      self.clear_pid unless @process_running
      @process_running
    end
    
    def start_process
      logger.warning "Executing start command: #{start_command}"
      
      if self.daemonize?
        starter = lambda { drop_privileges; ::Kernel.exec(start_command) }
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
      if stop_command
        cmd = stop_command.to_s.gsub("{{PID}}", actual_pid.to_s)
        logger.warning "Executing stop command: #{cmd}"
        
        system(cmd)
        
        skip_ticks_for(stop_grace_time)
        
      else
        logger.warning "Executing default stop command. Sending TERM signal to #{actual_pid}"
        
        signal_process("TERM")
  
        wait_until = Time.now.to_i + stop_grace_time
        while process_running?(true)
          if wait_until <= Time.now.to_i
            signal_process("KILL")
            break
          end
          sleep 0.2
        end
      end
      self.unlink_pid

      true
    end
    
    def restart_process
      if restart_command
        logger.warning "Executing restart command: #{restart_command}"
        system(restart_command)
        skip_ticks_for(restart_grace_time)
        
      else
        stop_process
        start_process
      end
      
      true
    end
    
    def daemonize?
      !!self.daemonize
    end
    
    def monitor_children?
      !!self.monitor_children
    end
    
    def signal_process(code)
      ::Process.kill(code, actual_pid)
      true
    rescue
      false
    end
    
    def actual_pid
      @actual_pid ||= begin
        File.read(pid_file).to_i if pid_file && File.exists?(pid_file)
      end
    end
    
    def actual_pid=(pid)
      @actual_pid = pid
    end
    
    def clear_pid
      @actual_pid = nil
    end
    
    def unlink_pid
      File.unlink(pid_file) if pid_file && File.exists?(pid_file)
    end
    
    def drop_privileges
      begin
        require 'etc'
        
        uid_num = Etc.getpwnam(self.uid).uid if self.uid
        gid_num = Etc.getgrnam(self.gid).gid if self.gid

        ::Process.groups = [gid_num] if self.gid
        ::Process::Sys.setgid(gid_num) if self.gid
        ::Process::Sys.setuid(uid_num) if self.uid
      rescue ArgumentError, Errno::EPERM, Errno::ENOENT => e
        # TODO: log exceptions elsewhere
        File.open("/tmp/exception.log", "w+"){|f| puts e}
      end
    end
    
    
    # Internal State Methods
    def skip_ticks_for(seconds)
      self.skip_ticks_until = (self.skip_ticks_until || Time.now.to_i) + seconds.to_i
    end
       
    def skipping_ticks?
      self.skip_ticks_until && self.skip_ticks_until > Time.now.to_i
    end
    
    def refresh_children!
      # First prune the list of dead children
      @children.delete_if {|child| !child.process_running?(true) }
      
      # Add new found children to the list
      new_children_pids = System.get_children(self.actual_pid) - @children.map {|child| child.actual_pid}
 
      logger.info "Existing children: #{@children.collect{|c| c.actual_pid}.join(",")}. Got new children: #{new_children_pids.inspect} for #{actual_pid}"
      
      # Construct a new process wrapper for each new found children
      new_children_pids.each do |child_pid|
        child = self.child_process_template.deep_copy
        
        child.name = "<child(pid:#{child_pid})>"
        child.actual_pid = child_pid
        child.logger = self.logger.prefix_with(child.name)
        
        child.initialize_state_machines
        child.state = "up"
        
        @children << child
      end
    end
    
    def deep_copy
      Marshal.load(Marshal.dump(self))
    end
  end
end
 