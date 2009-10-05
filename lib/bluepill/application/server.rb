module Bluepill
  module Application
    module ServerMethods
      
      def status
        buffer = ""
        self.processes.each do | process |
          buffer << "#{process.name} #{process.state}\n" +
        end
        buffer
      end

      def restart
        self.socket = Bluepill::Socket.new(name, base_dir).client      
        socket.send("restart\n", 0)
      end

      def stop
        self.socket = Bluepill::Socket.new(name, base_dir).client      
        socket.send("stop\n", 0)
      end
    end
  end
end