require "socket"

module Bluepill
  # The socket that the CLI sends a daemon its commands over
  #
  # @api private
  module Socket
    # Seconds a client command waits for the daemon's answer
    TIMEOUT = 60 # Used for client commands

    # Times a client command tries before it gives up
    MAX_ATTEMPTS = 5

    # Connect to an application's daemon
    #
    # @param [String] base_dir the directory with the daemons' sockets
    # @param [String] name the application's name
    #
    # @yield [socket] the work to do with the connection, which is closed
    #   after
    # @yieldparam [UNIXSocket] socket the connection
    # @yieldreturn [Object] what the block returns
    #
    # @return [Object] what the block returns
    #
    # @api private
    def self.client(base_dir, name, &block)
      UNIXSocket.open(socket_path(base_dir, name), &block)
    end

    # Send a command to an application's daemon, and return its answer
    #
    # It tries MAX_ATTEMPTS times when the daemon hangs up or takes longer
    # than TIMEOUT, and aborts after the last.
    #
    # @param [String] base_dir the directory with the daemons' sockets
    # @param [String] name the application's name
    # @param [String] command the command, such as start:group:process
    #
    # @return [Object] what the daemon answered, unmarshaled
    #
    # @api private
    def self.client_command(base_dir, name, command)
      res = nil
      MAX_ATTEMPTS.times do |current_attempt|
        begin
          res = send_command(base_dir, name, command)
          break
        rescue EOFError, Timeout::Error
          retry_or_abort(current_attempt)
        end
      end
      res
    end

    # Send a command to an application's daemon once, and return its answer
    #
    # It raises Timeout::Error if the daemon takes longer than TIMEOUT, and
    # EOFError if it hangs up.
    #
    # @param [String] base_dir the directory with the daemons' sockets
    # @param [String] name the application's name
    # @param [String] command the command, such as start:group:process
    #
    # @return [Object] what the daemon answered, unmarshaled
    #
    # @api private
    def self.send_command(base_dir, name, command)
      client(base_dir, name) do |socket|
        Timeout.timeout(TIMEOUT) do
          socket.puts command
          Marshal.load(socket.read)
        end
      end
    end

    # Say that a client command tries again, or abort after the last attempt
    #
    # @param [Integer] current_attempt the attempt that failed, from 0
    #
    # @return [void]
    #
    # @api private
    def self.retry_or_abort(current_attempt)
      abort("Socket Timeout: Server may not be responding") if current_attempt.eql?(MAX_ATTEMPTS - 1)
      puts "Retry #{current_attempt + 1} of #{MAX_ATTEMPTS}"
    end

    # Open the socket that an application's daemon listens on
    #
    # It replaces a socket file that no daemon answers on, and exits with
    # status 7 if a daemon already does.
    #
    # @param [String] base_dir the directory with the daemons' sockets
    # @param [String] name the application's name
    #
    # @return [UNIXServer]
    #
    # @api private
    def self.server(base_dir, name)
      # @type var path: String
      path = socket_path(base_dir, name)
      UNIXServer.open(path)
    rescue Errno::EADDRINUSE
      replace_stale_socket(path)
    end

    # Open a daemon's socket in place of a socket file that already exists
    #
    # It deletes the file and opens the socket if no daemon answers on it,
    # and exits with status 7 if a daemon does.
    #
    # @param [String] path the socket file
    #
    # @return [UNIXServer]
    #
    # @api private
    def self.replace_stale_socket(path)
      # if sock file has been created, test to see if there is a server
      UNIXSocket.open(path)
    rescue Errno::ECONNREFUSED
      File.delete(path)
      UNIXServer.open(path)
    else
      $stderr.puts("Server is already running!")
      exit(7)
    end

    # Return the path of an application's socket
    #
    # @param [String] base_dir the directory with the daemons' sockets
    # @param [String] name the application's name
    #
    # @return [String]
    #
    # @api private
    def self.socket_path(base_dir, name)
      File.join(base_dir, "socks", "#{name}.sock")
    end
  end
end
