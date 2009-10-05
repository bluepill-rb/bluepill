require 'logger'

module Bluepill
  class Application
    attr_accessor :name, :logger, :base_dir, :socket, :pid_file
    attr_accessor :groups, :group_logger
    
    def initialize(name, options = {})
      self.name = name
      self.base_dir = options[:base_dir] ||= '/var/bluepill'
      
      self.logger = Bluepill::Logger.new
      self.group_logger = Bluepill::Logger.new(self.logger, "#{self.name}:") if self.logger
      
      self.groups = Hash.new { |h,k| h[k] = Group.new(k, :logger => self.group_logger) }

      self.pid_file = File.join(self.base_dir, 'pids', self.name + ".pid")

      @server = false
      signal_trap
    end
    
    def start
      # Daemonize.daemonize
      File.open(self.pid_file, 'w') { |x| x.write(::Process.pid) }
      start_server
    end
    
    def status
      if(@server)
        logger.info("Server: GOT STATUS")
        buffer = ""
        self.groups.each do |name, group|
          buffer << "#{name}:\n" if name
          prefix = name ? "  " : ""
          group.status.each do |process_name, status|
            buffer << "#{prefix}#{process_name}: #{status}\n"
          end
          buffer << "\n"
        end
        buffer
      else
        send_to_server('status')
      end
    end
    
    def stop
      if(@server)
        logger.info("stop process")
      else
        send_to_server('stop')
      end
    end
    
    def unmonitor
      if(@server)
        self.groups.each do |group|
          group.unmonitor
        end
      else
        send_to_server('unmonitor')
      end
    end
    
    def add_process(process, group = nil)
      self.groups[group].add_process(process)
    end
    
    def send_to_server(method)
      self.socket = Bluepill::Socket.new(name, base_dir).client 
      socket.write(method + "\n")
      buffer = ""
      while(line = socket.gets)
        line << buffer
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
            response = app.send(cmd)
            puts response
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
      @server = true
      self.socket = Bluepill::Socket.new(name, base_dir).server
      $0 = "bluepill: #{self.name}"
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
   
   def grep_pattern(query)
     pattern = [self.name, query].join('|')
    'bluepill.*\[.*' + Regexp.escape(pattern) + '.*\]'
   end 

  end
end