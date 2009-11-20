module Bluepill
  class Application
    attr_accessor :name, :logger, :base_dir, :socket, :pid_file
    attr_accessor :groups, :work_queue, :socket_timeout

    def initialize(name, options = {})
      self.name = name
      self.base_dir = options[:base_dir] ||= '/var/bluepill'
      self.socket_timeout = options[:socket_timeout] ||= 10
      
      self.logger = Bluepill::Logger.new(options.slice(:log_file)).prefix_with(self.name)
      
      self.groups = Hash.new 

      self.pid_file = File.join(self.base_dir, 'pids', self.name + ".pid")
      
      @server = false
    end
        
    def load
      begin
        start_server
      rescue StandardError => e
        $stderr.puts "Failed to start bluepill:"
        $stderr.puts "%s `%s`" % [e.class.name, e.message]
        $stderr.puts e.backtrace
        exit(5)
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
        "Terminating bluepill[#{::Process.pid}]"
      else
        send_to_server("quit")
      end
    end
    
    def add_process(process, group_name = nil)
      self.groups[group_name] ||= Group.new(group_name, :logger => self.logger.prefix_with(group_name))
      self.groups[group_name].add_process(process)
    end
    
    def send_to_server(method)
      buffer = ""
      begin
        status = Timeout::timeout(self.socket_timeout) do
          self.socket = Bluepill::Socket.new(name, base_dir).client # Something that should be interrupted if it takes too much time...
          socket.write(method + "\n")
          while(line = socket.gets)
            buffer << line
          end
        end
      rescue Timeout::Error
        abort("Socket Timeout: Server may not be responding")
      rescue Errno::ECONNREFUSED
        abort("Connection Refused: Server is not running")
      end
      buffer
    end

    private

    def start_listener
      @listener_thread.kill if @listener_thread
      @listener_thread = Thread.new(self) do |app|
        begin
          loop do
            client = app.socket.accept
            cmd = client.readline.strip
            response = app.send(*cmd.split(":"))
            client.write(response)
            client.close
          end
        rescue StandardError => e
          logger.err("Got exception in cmd listener: %s `%s`" % [e.class.name, e.message])
          e.backtrace.each {|l| logger.err(l)}
        end
      end
    end
    
    def start_worker
      @worker_thread.kill if @worker_thread
      @worker_thread = Thread.new(self) do |app|
        loop do
          begin
            job = app.work_queue.pop
            send_to_process_or_group(job[0], job[1], false)
          rescue StandardError => e
            logger.err("Error while trying to execute %s from work_queue" % job.inspect)
            logger.err("%s: `%s`" % [e.class.name, e.message])
          end
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
        else
          5.times do |i|
            sleep 0.5
            break unless System.pid_alive?(previous_pid)
          end
          
          if System.pid_alive?(previous_pid)
            $stderr.puts "Previous bluepilld[#{previous_pid}] didn't die"
            exit(4)
          end
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
      start_listener
      start_worker
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
        File.unlink(self.socket.path) if self.socket
        File.unlink(self.pid_file) if File.exists?(self.pid_file)
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