module Bluepill
  # Starts, stops and restarts a Process with its configured commands
  #
  # @api private
  module ProcessCommands
    # Start the process with its start command
    #
    # Anything still running from an earlier start is killed first, and the
    # pre_start_command runs. A process bluepill daemonizes has its pid added
    # to the journal. A self-daemonizing one gets start_grace_time to finish,
    # and then on_start_timeout is dispatched. Ticks are skipped for
    # start_grace_time either way.
    #
    # @return [Integer] when ticks resume, in epoch seconds
    #
    # @api private
    def start_process
      # An old stop signal thread would otherwise signal and clean up the new process
      clean_threads
      ProcessJournal.kill_all_from_journal(name) # be sure nothing else is running from previous runs
      pre_start_process
      # ProcessFactory makes sure every process has a start command
      command = start_command #: String
      logger.warning "Executing start command: #{command}"
      if daemonize?
        daemon_id = System.daemonize(command, system_command_options)
        if daemon_id
          ProcessJournal.append_pid_to_journal(name, daemon_id)
          # Only refresh_children! fills children, and only when monitoring them
          children.each do |child|
            ProcessJournal.append_pid_to_journal(name, child.actual_pid)
          end
        end
      else
        # This is a self-daemonizing process
        with_timeout(start_grace_time, on_start_timeout) do
          run_command(command, 'Start')
        end
      end

      skip_ticks_for(start_grace_time)
    end

    # Run the pre_start_command, if there is one
    #
    # @return [void]
    #
    # @api private
    def pre_start_process
      return unless pre_start_command

      logger.warning "Executing pre start command: #{pre_start_command}"
      run_command(pre_start_command, 'Pre start')
    end

    # Stop the process with its stop command, stop signals, or TERM
    #
    # The children's pids go in the journal first, so cleanup kills them too.
    # Stop signals are sent from a thread of their own, with their delays.
    # Ticks are skipped for stop_grace_time.
    #
    # @return [Integer] when ticks resume, in epoch seconds
    #
    # @api private
    def stop_process
      if monitor_children
        System.get_children(actual_pid).each do |child_pid|
          ProcessJournal.append_pid_to_journal(name, child_pid)
        end
      end

      if stop_command
        cmd = prepare_command(stop_command)
        logger.warning "Executing stop command: #{cmd}"

        with_timeout(stop_grace_time, 'stop') do
          run_command(cmd, 'Stop')
        end
        cleanup_process
      elsif stop_signals
        # issue stop signals with configurable delay between each
        logger.warning "Sending stop signals to #{actual_pid}"
        @threads << Thread.new(stop_signals.clone) { |signals| send_stop_signals(signals) }
      else
        logger.warning "Executing default stop command. Sending TERM signal to #{actual_pid}"
        signal_process('TERM')
        cleanup_process
      end

      skip_ticks_for(stop_grace_time)
    end

    # Restart the process with its restart command, or by stopping and starting
    #
    # @return [Integer] when ticks resume, in epoch seconds
    #
    # @api private
    def restart_process
      if restart_command
        cmd = prepare_command(restart_command)

        logger.warning "Executing restart command: #{cmd}"

        with_timeout(restart_grace_time, 'restart') do
          run_command(cmd, 'Restart')
        end

        skip_ticks_for(restart_grace_time)
      else
        logger.warning 'No restart_command specified. Must stop and start to restart'
        stop_process
        # Stop signals run in a thread. Wait for them, or start_process would
        # kill the stopping process from the journal before its delays are up.
        @threads.each(&:join)
        start_process
      end
    end

    # Kill what's left of the process, and delete its pid file
    #
    # Bluepill only writes the pid file for processes it daemonizes, but it
    # removes it for every process, so a stopped process never leaves a stale
    # pid behind for a later process to reuse. It forgets the pid it cached
    # too, so a restart that stops and starts the process reads the new one.
    #
    # @return [void]
    #
    # @api private
    def cleanup_process
      ProcessJournal.kill_all_from_journal(name) # finish cleanup
      unlink_pid
      clear_pid
    end

    # Return a command with <tt>{{PID}}</tt> replaced by the process's pid
    #
    # @param [String] command the stop or restart command
    #
    # @return [String]
    #
    # @api private
    def prepare_command(command)
      command.gsub('{{PID}}', actual_pid.to_s)
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
        supplementary_groups: supplementary_groups,
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
      logger.err 'Execution is taking longer than expected.'
      logger.err 'Did you forget to tell bluepill to daemonize this process?'
      dispatch!(next_state)
    end

    # Run a command, and wait for it to finish
    #
    # A command that fails, or that a signal kills, is logged as a warning.
    #
    # @param [String] cmd the command
    # @param [String] description what the command is, for the log, such as
    #   Start
    #
    # @return [void]
    #
    # @api private
    def run_command(cmd, description)
      result = System.execute_blocking(cmd, system_command_options)
      # The exit code is nil when a signal killed the command
      exit_code = result.fetch(:exit_code)
      return if exit_code && exit_code.zero?

      logger.warning "#{description} command execution returned non-zero exit code:"
      logger.warning result.inspect
    end

    # Send stop signals, with their delays, until the process stops
    #
    # Sends the first signal, then each later one after its delay, as long as
    # the process is still running. Then gives the last signal the rest of
    # stop_grace_time to work before cleaning up.
    #
    # @param [Array<Symbol, Integer>] signals signals with the delays between
    #
    # @return [void]
    #
    # @api private
    def send_stop_signals(signals)
      remaining = stop_grace_time
      signal = signals.shift
      logger.info "Sending signal #{signal} to #{actual_pid}"
      signal_process(signal) # send first signal

      until signals.empty?
        # we already checked to make sure signals had an odd number of items
        delay = signals.shift #: Integer
        signal = signals.shift
        remaining -= delay

        logger.debug "Sleeping for #{delay} seconds"
        sleep delay
        # break unless signal_process(0) #break unless the process can be reached
        unless signal_process(0)
          logger.debug 'Process has terminated.'
          return cleanup_process
        end
        logger.info "Sending signal #{signal} to #{actual_pid}"
        signal_process(signal)
      end
      wait_for_stop(remaining)
      cleanup_process
    end

    # Wait for the process to exit, checking once a second
    #
    # It stops 2 seconds short of the grace time: ticks resume up to a second
    # early (they count whole seconds) and can kill this thread, and the
    # cleanup itself takes up to another second.
    #
    # @param [Integer, Float] seconds the grace time that's left
    #
    # @return [void]
    #
    # @api private
    def wait_for_stop(seconds)
      (seconds - 2).ceil.times do
        break unless signal_process(0)

        sleep 1
      end
    end
  end
end
