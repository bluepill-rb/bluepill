require 'socket'

module Bluepill
  module Socket
    TIMEOUT = 60 # Used for client commands
    MAX_ATTEMPTS = 5

  module_function

    def client(base_dir, name, &block)
      UNIXSocket.open(socket_path(base_dir, name), &block)
    end

    def client_command(base_dir, name, command)
      res = nil
      MAX_ATTEMPTS.times do |current_attempt|
        begin
          client(base_dir, name) do |socket|
            Timeout.timeout(TIMEOUT) do
              socket.puts command
              res = Marshal.load(socket.read)
            end
          end
          break
        rescue EOFError, Timeout::Error
          if current_attempt == MAX_ATTEMPTS - 1
            abort('Socket Timeout: Server may not be responding')
          end
          puts "Retry #{current_attempt + 1} of #{MAX_ATTEMPTS}"
        end
      end
      res
    end

    def server(base_dir, name)
      socket_path = self.socket_path(base_dir, name)
      UNIXServer.open(socket_path)
    rescue Errno::EADDRINUSE
      begin
        # if sock file has been created, test to see if there is a server
        UNIXSocket.open(socket_path)
      rescue Errno::ECONNREFUSED
        File.delete(socket_path)
        return UNIXServer.open(socket_path)
      else
        logger.err('Server is already running!')
        exit(7)
      end
    end

    def socket_path(base_dir, name)
      File.join(base_dir, 'socks', name + '.sock')
    end
  end
end
