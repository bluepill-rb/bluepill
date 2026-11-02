module Bluepill
  class Application
    # Answer the commands that the CLI sends over the daemon's socket
    #
    # Application is the only class that includes it.
    #
    # @api private
    module Listener
      protected

      # Start the thread that answers commands on the socket
      #
      # It kills the thread that a previous call started. Each command is a
      # line, such as start:group:process, and the answer is the command's
      # result, or the error it raised, marshaled.
      #
      # @return [Thread] the listener thread
      #
      # @api private
      def start_listener
        previous_thread = @listener_thread
        previous_thread.kill if previous_thread
        @listener_thread = Thread.new do
          loop do
            answer_next_client
          end
        end
      end

      # Accept a client on the socket, answer its command, and close it
      #
      # An error is logged, so the listener keeps going.
      #
      # @return [void]
      #
      # @api private
      def answer_next_client
        client = nil #: UNIXSocket?
        begin
          server = socket #: UNIXServer
          client = server.accept
          answer_command(client)
        rescue => e
          log_listener_error(e)
        ensure
          close_client(client)
        end
      end

      # Read a client's command, and write it the marshaled answer
      #
      # @param [UNIXSocket] client the client
      #
      # @return [void]
      #
      # @api private
      def answer_command(client)
        client.close_on_exec = true if client.respond_to?(:close_on_exec=)
        # The target is group:process and the process name may contain ':'
        command, *args = client.readline.strip.split(":", 3).reject(&:empty?)
        client.write(Marshal.dump(command_result(command, args)))
      end

      # Run a command while holding the daemon's lock, and return its result
      #
      # @param [String, nil] command the command
      # @param [Array<String>] args the group and process, for example
      #
      # @return [Object] what the command returned, or the error it raised
      #
      # @api private
      def command_result(command, args)
        method = daemon_command(command)
        mutex { public_send(method, *args) }
      rescue => e
        e
      end

      # Return the one of the DAEMON_COMMANDS that a client's command names
      #
      # Anyone who can write to the socket can send any line, so only these
      # commands may run, and not any other of the daemon's public methods.
      #
      # @param [String, nil] command the command, or nil for an empty line
      #
      # @raise [NoMethodError] if it names none of them
      #
      # @return [Symbol]
      #
      # @api private
      def daemon_command(command)
        DAEMON_COMMANDS.detect { |name| name.to_s.eql?(command) } ||
          raise(NoMethodError, "Unknown command `#{command}`")
      end

      # Log an error that answering a client raised, with its backtrace
      #
      # @param [StandardError] error the error
      #
      # @return [void]
      #
      # @api private
      def log_listener_error(error)
        logger.err(format("Got exception in cmd listener: %s `%s`", error.class.name, error.message))
        Array(error.backtrace).each { |l| logger.err(l) }
      end

      # Close a client, unless accepting it failed
      #
      # @param [UNIXSocket, nil] client the client, or nil
      #
      # @return [void]
      #
      # @api private
      def close_client(client)
        client.close if client
      rescue IOError
        # closed stream
      end
    end
  end
end
