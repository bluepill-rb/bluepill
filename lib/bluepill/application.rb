module Bluepill
  class Application
    attr_accessor :name, :logger, :base_dir, :socket, :pid_file
    attr_accessor :groups
    
    def initialize(name, options = {})
      self.name = name
      self.base_dir = options[:base_dir] ||= '/var/bluepill'
      
      self.logger = Bluepill::Logger.new.prefix_with(self.name)
      
      self.groups = Hash.new 

      self.pid_file = File.join(self.base_dir, 'pids', self.name + ".pid")

      @server = false
      signal_trap
    end
        
    def load
      start_server
    end
    
    def status
      if(@server)
        buffer = ""
        if self.groups.has_key?(nil)
          self.groups[nil].status.each do |line|
            buffer << "%s: %s\n" % line
          end
          buffer << "\n"
        end
        self.groups.keys.compact.sort.each do |name|
          group = self.groups[name]
          buffer << "#{name}:\n"
          group.status.each { |line| buffer << "  %s: %s\n" % line }
          buffer << "\n"
        end
        buffer
      else
        send_to_server('status')
      end
    end
    
    def stop(process_or_group_name)
      if(@server)
        group = self.groups[process_or_group_name]
        
        if group
          group.stop
          
        else
          self.groups.values.each do |group|
            group.stop(process_or_group_name)
          end
        end
        "ok"
      else
        send_to_server("stop:#{process_or_group_name}")
      end
    end
    
    def start(process_or_group_name)
      if(@server)
        group = self.groups[process_or_group_name]
        
        if group
          group.start
          
        else
          self.groups.values.each do |group|
            group.start(process_or_group_name)
          end
        end
        "ok"
      else
        send_to_server("start:#{process_or_group_name}")
      end
    end

    def restart(process_or_group_name)
      if(@server)
        group = self.groups[process_or_group_name]
        
        if group
          group.restart
          
        else
          self.groups.values.each do |group|
            group.restart(process_or_group_name)
          end
        end
        "ok"
      else
        send_to_server("restart:#{process_or_group_name}")
      end
    end

    def unmonitor(process_or_group_name)
      if(@server)
        group = self.groups[process_or_group_name]
        
        if group
          group.unmonitor
          
        else
          self.groups.values.each do |group|
            group.unmonitor(process_or_group_name)
          end
        end
        "ok"
      else
        send_to_server("unmonitor:#{process_or_group_name}")
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
            logger.info("Server | Command loop started:")
            client = socket.accept
            logger.info("Server: Handling Request")
            cmd = client.readline.strip
            logger.info("Server: #{cmd}")
            response = app.send(*cmd.split(":"))
            logger.info("Server: Sending Response")
            client.write(response)
            client.close
          end
        rescue Exception => e
          logger.info(e.inspect)
        end
      end
    end

    def start_server
      if File.exists?(self.pid_file)
        previous_pid = File.read(self.pid_file).to_i
        begin
          puts "Killing previous bluepilld[#{previous_pid}]"
          ::Process.kill(2, previous_pid)
        rescue Exception => e
          exit unless e.is_a?(Errno::ESRCH)
          # it was probably already dead
        end
        sleep 1 # wait for it to die
      end
      
      Daemonize.daemonize
      
      @server = true
      self.socket = Bluepill::Socket.new(name, base_dir).server
      File.open(self.pid_file, 'w') { |x| x.write(::Process.pid) }
      $0 = "bluepilld: #{self.name}"
      self.groups.each {|name, group| group.start }
      listener
      run
    end
    
    def run
      loop do
        self.groups.each do |_, group|
          group.tick
        end
        sleep 1
      end
    end
        
    def cleanup
      # self.socket.cleanup
    end
    
    def signal_trap
      
      terminator = lambda do
        puts "Terminating..."
        cleanup
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