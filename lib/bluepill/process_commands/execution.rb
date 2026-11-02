# frozen_string_literal: true

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
      def prepare_command(command) = substitute_pid(command, actual_pid)

      # Return a command with <tt>{{PID}}</tt> replaced by a pid
      #
      # @param [String] command the command
      # @param [Integer, nil] pid the pid, or nil for an empty one
      #
      # @return [String]
      #
      # @api private
      def substitute_pid(command, pid) = command.gsub("{{PID}}", pid.to_s)

      # Return the options the process's commands run with
      #
      # @return [System::CommandOptions] its uid, gid, supplementary_groups,
      #   working_dir, environment, stdin, stdout and stderr
      #
      # @api private
      def command_options
        System::CommandOptions.new(
          uid: uid, gid: gid, supplementary_groups: supplementary_groups, working_dir: working_dir,
          environment: environment, stdin: stdin, stdout: stdout, stderr: stderr
        )
      end

      # Run a block, and dispatch an event if it takes too long
      #
      # @param [Integer, Float] secs how long the block may take
      # @param [Symbol] next_state the event to dispatch if it times out
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
      # @param [System::CommandOptions] options how to run it
      #
      # @return [void]
      #
      # @api private
      def run_command(cmd, description, options = command_options)
        result = System.execute_blocking(cmd, options)
        return if result.success?

        logger.warning "#{description} command execution returned non-zero exit code:"
        logger.warning result.to_h.inspect
      end
    end
  end
end
