# frozen_string_literal: true

module Bluepill
  module ProcessCommands
    # Runs the commands a Process has around its starts and stops, and on
    # each change of state
    #
    # Each runs for up to hook_timeout, and one that fails or times out is
    # only logged.
    #
    # @api private
    module Hooks
      # Run the pre_start_command, if there is one, and wait for it
      #
      # The start waits for up to hook_timeout, and goes ahead either way.
      # The process has no pid yet, so <tt>{{PID}}</tt> becomes nothing.
      #
      # @return [void]
      #
      # @api private
      def pre_start_process
        command = pre_start_command
        run_hook(command, "Pre start", nil) if command
      end

      # Run the pre_stop_command, if there is one, and wait for it
      #
      # The stop waits for up to hook_timeout, and goes ahead either way.
      #
      # @return [void]
      #
      # @api private
      def pre_stop_process
        command = pre_stop_command
        run_hook(command, "Pre stop", stopping_pid) if command
      end

      # Run the post_stop_command in the background, if there is one
      #
      # @return [Thread, nil] the thread that runs it
      #
      # @api private
      def post_stop_process
        command = post_stop_command
        run_hook_in_background(command, "Post stop", stopping_pid) if command
      end

      # Run the post_start_command in the background, if there is one
      #
      # @return [Thread, nil] the thread that runs it
      #
      # @api private
      def post_start_process
        command = post_start_command
        run_hook_in_background(command, "Post start", actual_pid) if command
      end

      # Run the notify_command in the background, after a change of state
      #
      # The command gets the details in environment variables. A loopback, such
      # as up to up, isn't a change, so it runs nothing.
      #
      # @param [#from_name, #to_name, #loopback?] transition the transition
      #
      # @return [Thread, nil] the thread that runs it
      #
      # @api private
      def notify_transition(transition)
        command = notify_command
        return if command.nil? || transition.loopback?

        pid = cached_pid
        run_hook_in_background(command, "Notify", pid, notify_environment(transition, pid))
      end

      # Return the environment variables notify_command gets for a transition
      #
      # @param [#from_name, #to_name] transition the transition
      # @param [Integer, nil] pid the process's pid, or the last one it had
      #
      # @return [Hash{String => String}] BLUEPILL_APP, BLUEPILL_GROUP,
      #   BLUEPILL_PROCESS, BLUEPILL_FROM, BLUEPILL_TO, BLUEPILL_REASON and
      #   BLUEPILL_PID
      #
      # @api private
      def notify_environment(transition, pid)
        {
          "BLUEPILL_APP" => app_name.to_s,
          "BLUEPILL_GROUP" => group_name.to_s,
          "BLUEPILL_PROCESS" => name.to_s,
          "BLUEPILL_FROM" => transition.from_name.to_s,
          "BLUEPILL_TO" => transition.to_name.to_s,
          "BLUEPILL_REASON" => transition_reason.to_s,
          "BLUEPILL_PID" => pid.to_s
        }
      end

      # Run a hook command in a thread of its own
      #
      # @param [String] command the command
      # @param [String] description what the hook is, for the log
      # @param [Integer, nil] pid what <tt>{{PID}}</tt> in the command becomes
      # @param [Hash{String => String}] env more environment variables
      #
      # @return [Thread] the thread that runs it
      #
      # @api private
      def run_hook_in_background(command, description, pid, env = {})
        Thread.new { run_hook(command, description, pid, env) }
      end

      # Run a hook command, and wait for it for up to hook_timeout
      #
      # The command runs like the process's other commands, with its
      # working_dir, environment, uid and gid. A hook that runs longer than
      # hook_timeout is killed, with anything it started. A hook that fails or
      # times out is logged, and never changes what bluepill does with the
      # process.
      #
      # @param [String] command the command
      # @param [String] description what the hook is, for the log
      # @param [Integer, nil] pid what <tt>{{PID}}</tt> in the command becomes
      # @param [Hash{String => String}] env more environment variables
      #
      # @return [void]
      #
      # @api private
      def run_hook(command, description, pid, env = {})
        cmd = substitute_pid(command, pid)
        logger.info "Executing #{description.downcase} command: #{cmd}"
        run_command(cmd, description, hook_options(env))
      rescue Timeout::Error
        logger.warning "#{description} command took longer than #{hook_timeout} seconds: #{command}"
      rescue => e
        logger.err "#{description} command failed: #{e}"
      end

      # Return the options a hook command runs with
      #
      # They're the process's command options, with more environment variables
      # and hook_timeout.
      #
      # @param [Hash{String => String}] env more environment variables
      #
      # @return [Hash{Symbol => Object}] the options, as system_command_options
      #   returns, with :timeout
      #
      # @api private
      def hook_options(env)
        options = system_command_options
        options[:environment] = (environment || {}).merge(env)
        options[:timeout] = hook_timeout
        options
      end

      private

      # Return the pid of the process being stopped
      #
      # stop_process reads it before cleanup forgets it, for the stop hooks.
      #
      # @return [Integer, nil]
      #
      # @api private
      attr_reader :stopping_pid

      # Return why the process is changing state, while dispatch! runs
      #
      # @return [String, nil] the reason, such as "user initiated", or nil
      #   when none was given
      #
      # @api private
      attr_reader :transition_reason

      # Return the process's pid, or the last one it had if it has died
      #
      # A process that has died has no pid by the time its state changes,
      # but notify_command still gets the one it had.
      #
      # @return [Integer, nil]
      #
      # @api private
      def cached_pid
        @actual_pid || @last_pid
      end
    end
  end
end
