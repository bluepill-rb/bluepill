module Bluepill
  # Starts, stops and restarts a Process with its configured commands
  module ProcessCommands
    def start_process
      ProcessJournal.kill_all_from_journal(name) # be sure nothing else is running from previous runs
      pre_start_process
      logger.warning "Executing start command: #{start_command}"
      if daemonize?
        daemon_id = System.daemonize(start_command, system_command_options)
        if daemon_id
          ProcessJournal.append_pid_to_journal(name, daemon_id)
          if monitor_children?
            children.each do |child|
              ProcessJournal.append_pid_to_journal(name, child.actual_pid)
            end
          end
        end
        daemon_id
      else
        # This is a self-daemonizing process
        with_timeout(start_grace_time, on_start_timeout) do
          run_command(start_command, 'Start')
        end
      end

      skip_ticks_for(start_grace_time)
    end

    def pre_start_process
      return unless pre_start_command

      logger.warning "Executing pre start command: #{pre_start_command}"
      run_command(pre_start_command, 'Pre start')
    end

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
        @threads << Thread.new(self, stop_signals.clone) { |process, signals| send_stop_signals(process, signals) }
      else
        logger.warning "Executing default stop command. Sending TERM signal to #{actual_pid}"
        signal_process('TERM')
        cleanup_process
      end

      skip_ticks_for(stop_grace_time)
    end

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
        start_process
      end
    end

    def cleanup_process
      ProcessJournal.kill_all_from_journal(name) # finish cleanup
      # Bluepill only writes the pid file for processes it daemonizes, but it
      # removes it for every process, so a stopped process never leaves a stale
      # pid behind for a later process to reuse
      unlink_pid
    end

    def prepare_command(command)
      command.to_s.gsub('{{PID}}', actual_pid.to_s)
    end

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

    def with_timeout(secs, next_state = nil, &blk)
      # Attempt to execute the passed block. If the block takes
      # too long, transition to the indicated next state.
      Timeout.timeout(secs.to_f, &blk)
    rescue Timeout::Error
      logger.err 'Execution is taking longer than expected.'
      logger.err 'Did you forget to tell bluepill to daemonize this process?'
      dispatch!(next_state)
    end

    def run_command(cmd, description)
      result = System.execute_blocking(cmd, system_command_options)
      return if result[:exit_code].zero?

      logger.warning "#{description} command execution returned non-zero exit code:"
      logger.warning result.inspect
    end

    # Sends the first signal, then each later one after its delay, as long as
    # the process is still running
    def send_stop_signals(process, signals)
      signal = signals.shift
      logger.info "Sending signal #{signal} to #{process.actual_pid}"
      process.signal_process(signal) # send first signal

      until signals.empty?
        # we already checked to make sure signals had an odd number of items
        delay = signals.shift
        signal = signals.shift

        logger.debug "Sleeping for #{delay} seconds"
        sleep delay
        # break unless signal_process(0) #break unless the process can be reached
        unless process.signal_process(0)
          logger.debug 'Process has terminated.'
          break
        end
        logger.info "Sending signal #{signal} to #{process.actual_pid}"
        process.signal_process(signal)
      end
      cleanup_process
    end
  end
end
