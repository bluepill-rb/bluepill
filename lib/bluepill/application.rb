require 'logger'

module Bluepill
  class Application
    attr_accessor :name, :logger, :bp_dir, :socket, :processes, :pid_file
    
    def initialize(name, options = {})
      self.processes = []
      self.name = name
      self.bp_dir = options["bp_dir"] ||= '/var/bluepill'
      self.logger = Bluepill::Logger.new
      self.pid_file = File.join(self.bp_dir, 'pids', self.name + ".pid")
      @server = false
      signal_trap
    end
    
    def method_missing(method_name, *args)
      self.socket = Bluepill::Socket.new(name, bp_dir).client      
      socket.send(method_name.to_s + "\n", 0)
      socket.recvfrom(255)
      socket.close
    end

    def run
      loop do
        self.processes.each do |process|
          process.tick
        end
        sleep 1
      end
    end

    def start
      # Daemonize.daemonize
      File.open(self.pid_file, 'w') { |x| x.write(::Process.pid) }
      start_server
    end
    
    def status
      if(@server)
        buffer = ""
        self.processes.each do | process |
          buffer << "#{process.name} #{process.state}\n" +
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
        self.processes.each do |process|
          process.unmonitor
        end
      else
        send_to_server('unmonitor')
      end
    end
private

    def listener
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

    def start_server
      @server = true
      self.socket = Bluepill::Socket.new(name, bp_dir).server
      listener
      run
    end
    
    def run
      loop do
        logger.info("#{name} hi")
        sleep(10)
      end
    end
    
    def cleanup
      self.socket.cleanup
    end
    
    def signal_trap
      Signal.trap("TERM") do
        puts "Terminating..."
        cleanup
        shutdown()
      end
    end
    
  end
end