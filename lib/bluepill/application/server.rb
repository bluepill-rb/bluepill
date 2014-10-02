# -*- encoding: utf-8 -*-
module Bluepill
  module Application
    module ServerMethods

      def status
        self.processes.collect do |process|
          "#{process.name} #{process.state}"
        end.join("\n")
      end

      def restart
        socket_send('restart')
      end

      def stop
        socket_send('stop')
      end

      private

      def socket_send(msg)
        self.socket = Bluepill::Socket.new(name, base_dir).client
        socket.send("#{msg}\n", 0)
      end

    end
  end
end
