require 'socket'

module Bluepill
  module Socket
    TIMEOUT = 60 # Used for client commands
    MAX_ATTEMPTS = 5

    def self.client(base_dir, name, &block)
      UNIXSocket.open(socket_path(base_dir, name), &block)
    end

    def self.client_command(base_dir, name, command)
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
          abort('Socket Timeout: Server may not be responding') if current_attempt.eql?(MAX_ATTEMPTS - 1)
          puts "Retry #{current_attempt + 1} of #{MAX_ATTEMPTS}"
        end
      end
      res
    end

    def self.server(base_dir, name)
      # @type var path: String
      path = socket_path(base_dir, name)
      UNIXServer.open(path)
    rescue Errno::EADDRINUSE
      begin
        # if sock file has been created, test to see if there is a server
        UNIXSocket.open(path)
      rescue Errno::ECONNREFUSED
        File.delete(path)
        UNIXServer.open(path)
      else
        $stderr.puts('Server is already running!')
        exit(7)
      end
    end

    def self.socket_path(base_dir, name)
      File.join(base_dir, 'socks', "#{name}.sock")
    end
  end
end
