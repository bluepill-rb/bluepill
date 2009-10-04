require 'logger'

module Bluepill
  class Application
    attr_accessor :name, :logger, :bp_dir, :socket
    
    def initialize(name, options = {})
      self.name = name
      self.bp_dir = options["bp_dir"] ||= '/var/bluepill'
      self.logger = Logger.new("/tmp/bp.log")
      signal_trap
    end
        
    def start
      child_pid = fork
      if child_pid.nil?
        start_child 
        File.open(File.join(self.bp_dir, 'pids', self.name + ".pid"), 'w') do |x|
          x.write(child_pid)
        end
      end
    end
    
    def start_child
      self.socket = Bluepill::Socket.new(name, bp_dir).server
      command_loop
      run
    end

    def restart
      self.socket = Bluepill::Socket.new(name, bp_dir).client      
      socket.send("restart\n", 0)
    end
    
    def stop
      self.socket = Bluepill::Socket.new(name, bp_dir).client      
      socket.send("stop\n", 0)
    end
    
    def method_missing(method_name, *args)
      self.socket = Bluepill::Socket.new(name, bp_dir).client      
      socket.send(method_name.to_s + "\n", 0)
      socket.recvfrom(255)
      socket.close
    end
    
    def run
      loop do
        logger.info("#{name} hi")
        sleep(10)
      end
    end
    
    def command_loop
      Thread.new do
        begin
          loop do
            logger.info("Server | Command loop started:")
            logger.info
            client = socket.accept
            logger.info("Server | Connection accepted: #{client}")
            info = client.recvfrom(180)
            logger.info("#{name}: #{info}")
            client.send("#{name}: got #{info} returned ok\n", 0)
          end
        rescue Exception => e
          logger.info(e.inspect)
        end
      end
    end
    
    def signal_trap
      Signal.trap("TERM") do
        puts "Terminating..."
        shutdown()
      end
    end
    
  end
end