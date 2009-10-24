module Bluepill
  class Application
    attr_accessor :name, :logger, :base_dir, :socket, :pid_file
    attr_accessor :groups, :work_queue

    def initialize(name, options = {})
      self.name = name
      self.base_dir = options[:base_dir] ||= '/var/bluepill'
      
      self.logger = Bluepill::Logger.new.prefix_with(self.name)
      
      self.groups = Hash.new 

      self.pid_file = File.join(self.base_dir, 'pids', self.name + ".pid")

      @server = false
    end
        
    def load
      begin
        start_server
      rescue StandardError => e
        logger.err("Got exception: %s `%s`" % [e.class.name, e.message])
        e.backtrace.each {|l| logger.err(l)}
      end
    end
    
    def status
      if(@server)
        buffer = []
        depth = 0
        
        if self.groups.has_key?(nil)
          self.groups[nil].processes.each do |p|
            buffer << "%s%s(pid:%s): %s" % [" " * depth, p.name, p.actual_pid.inspect, p.state]
            
            if p.monitor_children?
              depth += 2
              p.children.each do |c|
                buffer << "%s%s: %s" % [" " * depth, c.name, c.state]
              end
              depth -= 2
            end
          end
        end

        self.groups.each do |group_name, group|
          next if group_name.nil?
          
          buffer << "\n#{group_name}"
          
          group.processes.each do |p|
            depth += 2
            
            buffer << "%s%s(pid:%s): %s" % [" " * depth, p.name, p.actual_pid.inspect, p.state]
            
            if p.monitor_children?
              depth += 2
              p.children.each do |c|
                buffer << "%s%s: %s" % [" " * depth, c.name, c.state]
              end
              depth -= 2
            end
            
            depth -= 2
          end
        end
        
        buffer.join("\n")
        
      else
        send_to_server('status')
      end
    end
    
    def stop(process_or_group_name)
      send_to_process_or_group(:stop, process_or_group_name)
    end
    
    def start(process_or_group_name)
      send_to_process_or_group(:start, process_or_group_name)
    end

    def restart(process_or_group_name)
      send_to_process_or_group(:restart, process_or_group_name)
    end

    def unmonitor(process_or_group_name)
      send_to_process_or_group(:unmonitor, process_or_group_name)
    end
    
    def send_to_process_or_group(method, process_or_group_name, async = true)      
      if(@server)
        if async
          self.work_queue.push([method, process_or_group_name])
        else
          group = self.groups[process_or_group_name]
          if group
            group.send(method)  
          else
            self.groups.values.each do |group|
              group.send(method, process_or_group_name)
            end
          end
        end
        return "ok"
      else
        send_to_server("#{method}:#{process_or_group_name}")
      end
    end
    
    def quit
      if @server
        ::Process.kill("TERM", 0)
      else
        send_to_server("quit")
      end
    end
    
    def add_process(process, group_name = nil)
      self.groups[group_name] ||= Group.new(group_name, :logger => self.logger.prefix_with(group_name))
      self.groups[group_name].add_process(process)
    end
    
    def send_to_server(method)
      self.socket = Bluepill::Socket.new(name, base_dir).client 
      socket.write(method + "\n")
      buffer = ""
      while(line = socket.gets)
        buffer << line
      end
      return buffer
    end

private

    def listener
      Thread.new(self) do |app|
        begin
          loop do
            # logger.info("Server | Command loop started:")
            client = socket.accept
            # logger.info("Server: Handling Request")
            cmd = client.readline.strip
            # logger.info("Server: #{cmd}")
            response = app.send(*cmd.split(":"))
            # logger.info("Server: Sending Response")
            client.write(response)
            client.close
          end
        rescue StandardError => e
          logger.err("Got exception in cmd listener: %s `%s`" % [e.class.name, e.message])
          e.backtrace.each {|l| logger.err(l)}
        end
      end
    end
    
    def worker
      Thread.new(self) do |app|
        loop do
          begin
            # app.logger.info("Server | worker loop started:")
            job = app.work_queue.pop
            send_to_process_or_group(job[0], job[1], false)
            
          rescue StandardError => e
            logger.err("Error while trying to execute %s from work_queue" % job.inspect)
            logger.err("%s: `%s`" % [e.class.name, e.message])
          end
          # app.logger.info("Server | worker job processed:")  
        end
      end
    end
    
    def start_server
      if File.exists?(self.pid_file)
        previous_pid = File.read(self.pid_file).to_i
        begin
          ::Process.kill(0, previous_pid)
          puts "Killing previous bluepilld[#{previous_pid}]"
          ::Process.kill(2, previous_pid)
        rescue Exception => e
          exit unless e.is_a?(Errno::ESRCH)
          # it was probably already dead
        else
          sleep 1 # wait for it to die
        end
      end
      
      Daemonize.daemonize
      
      @server = true
      $0 = "bluepilld: #{self.name}"
      
      self.work_queue = Queue.new
      
      self.socket = Bluepill::Socket.new(name, base_dir).server
      File.open(self.pid_file, 'w') { |x| x.write(::Process.pid) }
      
      self.groups.each {|_, group| group.boot! }
      
      setup_signal_traps
      listener
      worker
      run
    end
    
    def run
      loop do
        System.reset_data
        
        self.groups.each do |_, group|
          group.tick
        end
        sleep 1
      end
    end
    
    def setup_signal_traps
      terminator = lambda do
        puts "Terminating..."
        ::Kernel.exit
      end
      
      Signal.trap("TERM", &terminator) 
      Signal.trap("INT", &terminator) 
    end
   
    def grep_pattern(query = nil)
      bluepilld = 'bluepilld\[[[:digit:]]+\]:[[:space:]]+'
      pattern = [self.name, query].compact.join(':')
      [bluepilld, '\[.*', Regexp.escape(pattern), '.*'].join
    end
  end
end