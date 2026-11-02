module Bluepill
  module ProcessCommands
    # Runs a Process's commands as its user, in its working_dir, with its
    # environment and standard streams
    #
    # @api private
    module Execution
      # Return a command with <tt>{{PID}}</tt> replaced by the process's pid
      #
      # @param [String] command the stop or restart command
      #
      # @return [String]
      #
      # @api private
      def prepare_command(command)
        command.gsub("{{PID}}", actual_pid.to_s)
      end

      # Return the options the process's commands run with
      #
      # @return [Hash{Symbol => Object}] the uid, gid, working_dir, environment,
      #   pid_file, logger, stdin, stdout, stderr and supplementary_groups
      #
      # @api private
      def system_command_options
        {
          uid: uid,
          gid: gid,
          working_dir: working_dir,
          environment: environment,
          pid_file: pid_file,
          logger: logger,
          stdin: stdin,
          stdout: stdout,
          stderr: stderr,
          supplementary_groups: supplementary_groups
        }
      end

      # Run a block, and dispatch an event if it takes too long
      #
      # @param [Integer, Float] secs how long the block may take
      # @param [String, Symbol] next_state the event to dispatch if it times out
      #
      # @yield the work to time
      # @yieldparam [Numeric] secs the time limit
      #
      # @return [Object, Boolean] what the block returned, or whether the event's
      #   transition happened
      #
      # @api private
      def with_timeout(secs, next_state, &blk)
        Timeout.timeout(secs, &blk)
      rescue Timeout::Error
        logger.err "Execution is taking longer than expected."
        logger.err "Did you forget to tell bluepill to daemonize this process?"
        dispatch!(next_state)
      end

      # Run a command, and wait for it to finish
      #
      # A command that fails, or that a signal kills, is logged as a warning.
      #
      # @param [String] cmd the command
      # @param [String] description what the command is, for the log, such as
      #   Start
      # @param [Hash{Symbol => Object}] options how to run it, as
      #   system_command_options returns
      #
      # @return [void]
      #
      # @api private
      def run_command(cmd, description, options = system_command_options)
        result = System.execute_blocking(cmd, options)
        # The exit code is nil when a signal killed the command
        exit_code = result.fetch(:exit_code)
        return if exit_code && exit_code.zero?

        logger.warning "#{description} command execution returned non-zero exit code:"
        logger.warning result.inspect
      end
    end
  end
end
