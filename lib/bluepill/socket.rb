require 'socket'

module Bluepill
  module Socket
    TIMEOUT = 10

    extend self

    def client(base_dir, name, &b)
      UNIXSocket.open(socket_path(base_dir, name), &b)
    end
    
    def client_command(base_dir, name, command)
      client(base_dir, name) do |socket|
        Timeout.timeout(TIMEOUT) do
          socket.puts command
          Marshal.load(socket)
        end
      end
    rescue EOFError, Timeout::Error
      abort("Socket Timeout: Server may not be responding")
    end
    
    def server(base_dir, name)
      socket_path = self.socket_path(base_dir, name)
      begin
        UNIXServer.open(socket_path)
      rescue Errno::EADDRINUSE
        # if sock file has been created.  test to see if there is a server
        begin
          UNIXSocket.open(socket_path)
        rescue Errno::ECONNREFUSED
          File.delete(socket_path)
          return UNIXServer.open(socket_path)
        else
          logger.err("Server is already running!")
          exit(7)
        end
      end
    end
    
    def socket_path(base_dir, name)
      File.join(base_dir, 'socks', name + ".sock") 
    end
  end
end
 