module Bluepill
  class Application
    attr_accessor :name, :logger, :child_pid
    
    def initialize(name, options = {})
      self.name = name
      self.bp_dir = options["bp_dir"] ||= '/var/bluepill'
      self.logger = Logger.new("/tmp/bp.log")
      socket = Bluepill::Socket.new(name, bp_dir)
      signal_trap

    end
    
    def fork!
      command_loop
    end
    
    def run
      loop do
        logger.info("#{name} hi")
        sleep(10)
      end
    end
    
    def command_loop
      Thread.new do
        socket.gets do |x|
          logger.info("#{name}: #{x}")
          socket.write("#{name}: got #{x} returned ok\n")
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