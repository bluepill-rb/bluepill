# -*- encoding: utf-8 -*-
require 'socket'

module Bluepill
  module Socket
    TIMEOUT = 60 # Used for client commands
    MAX_ATTEMPTS = 5

    extend self

    def client(base_dir, name, &block)
      UNIXSocket.open(socket_path(base_dir, name), &block)
    end

    def client_command(base_dir, name, command, retry_limit=MAX_ATTEMPTS, timeout=TIMEOUT)
      client(base_dir, name) do |socket|
        Timeout.timeout(timeout) do
          socket.puts command
          Marshal.load(socket.read)
        end
      end
    rescue EOFError, Timeout::Error
      retry_limit -= 1
      abort("Socket Timeout: Server may not be responding") if retry_limit == 0
      puts "Retry #{current_attempt + 1} of #{MAX_ATTEMPTS}"
      retry
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
