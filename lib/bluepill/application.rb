module Bluepill
  class Application
    PROCESS_COMMANDS = [:start, :stop, :restart, :unmonitor]
    
    attr_accessor :name, :logger, :base_dir, :socket, :pid_file
    attr_accessor :groups, :work_queue
    attr_accessor :pids_dir, :log_file

    def initialize(name, options = {})
      self.name = name

      self.log_file = options[:log_file]      
      self.base_dir = options[:base_dir] || '/var/bluepill'
      self.pid_file = File.join(self.base_dir, 'pids', self.name + ".pid")
      self.pids_dir = File.join(self.base_dir, 'pids', self.name)

      self.groups = {}
      
      self.logger = Bluepill::Logger.new(:log_file => self.log_file).prefix_with(self.name)
      
      self.setup_signal_traps
      self.setup_pids_dir
    end
        
    def load
      begin
        self.start_server
      rescue StandardError => e
        $stderr.puts "Failed to start bluepill:"
        $stderr.puts "%s `%s`" % [e.class.name, e.message]
        $stderr.puts e.backtrace
        exit(5)
      end
    end
    
    def status
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
    end
    
    PROCESS_COMMANDS.each do |command|
      class_eval <<-END
        def #{command}(group_name, process_name = nil)
          self.send_to_process_or_group(:#{command}, group_name, process_name)
        end
      END
    end
    
    def add_process(process, group_name = nil)
      group_name = group_name.to_s if group_name
      
      self.groups[group_name] ||= Group.new(group_name, :logger => self.logger.prefix_with(group_name))
      self.groups[group_name].add_process(process)
    end

    protected
    def send_to_process_or_group(method, group_name, process_name)
      if self.groups.key?(group_name)
        self.groups[group_name].send(method, process_name)
      elsif process_name.nil?
        # they must be targeting just by process name
        process_name = group_name
        self.groups.values.collect do |group|
          group.send(method, process_name)
        end.flatten
      else
        []
      end
    end

    def start_listener
      @listener_thread.kill if @listener_thread
      @listener_thread = Thread.new do
        begin
          loop do
            client = self.socket.accept
            command, *args = client.readline.strip.split(":")
            response = self.send(command, *args)
            client.write(Marshal.dump(response))
            client.close
          end
        rescue StandardError => e
          logger.err("Got exception in cmd listener: %s `%s`" % [e.class.name, e.message])
          e.backtrace.each {|l| logger.err(l)}
        end
      end
    end
    
    def start_server
      self.kill_previous_bluepill
      
      Daemonize.daemonize
      
      self.logger.reopen
      
      $0 = "bluepilld: #{self.name}"
      
      self.groups.each {|_, group| group.boot }

      
      self.write_pid_file
      self.socket = Bluepill::Socket.server(self.base_dir, self.name)
      self.start_listener
      
      self.run
    end
    
    def run
      @running = true # set to false by signal trap
      while @running
        System.reset_data
        self.groups.each { |_, group| group.tick }
        sleep 1
      end
      cleanup
    end
    
    def cleanup
      File.unlink(self.socket.path) if self.socket
      File.unlink(self.pid_file) if File.exists?(self.pid_file)
    end
    
    def setup_signal_traps
      terminator = lambda do
        puts "Terminating..."
        @running = false
      end
      
      Signal.trap("TERM", &terminator) 
      Signal.trap("INT", &terminator) 
      
      Signal.trap("HUP") do
        self.logger.reopen if self.logger
      end
    end
    
    def setup_pids_dir
      FileUtils.mkdir_p(self.pids_dir) unless File.exists?(self.pids_dir)
      # we need everybody to be able to write to the pids_dir as processes managed by
      # bluepill will be writing to this dir after they've dropped privileges
      FileUtils.chmod(0777, self.pids_dir)
    end
    
    def kill_previous_bluepill
      if File.exists?(self.pid_file)
        previous_pid = File.read(self.pid_file).to_i
        begin
          ::Process.kill(0, previous_pid)
          puts "Killing previous bluepilld[#{previous_pid}]"
          ::Process.kill(2, previous_pid)
        rescue Exception => e
          $stderr.puts "Encountered error trying to kill previous bluepill:"
          $stderr.puts "#{e.class}: #{e.message}"
          exit(4) unless e.is_a?(Errno::ESRCH)
        else
          10.times do |i|
            sleep 0.5
            break unless System.pid_alive?(previous_pid)
          end
          
          if System.pid_alive?(previous_pid)
            $stderr.puts "Previous bluepilld[#{previous_pid}] didn't die"
            exit(4)
          end
        end
      end
    end
    
    def write_pid_file
      File.open(self.pid_file, 'w') { |x| x.write(::Process.pid) }
    end
  end
end