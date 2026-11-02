require "bluepill/process_commands/execution"
require "bluepill/process_commands/hooks"
require "bluepill/process_commands/stop_signals"

module Bluepill
  # Starts, stops and restarts a Process with its configured commands
  #
  # @api private
  module ProcessCommands
    include Execution
    include Hooks
    include StopSignals

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
          run_command(command, "Start")
        end
      end

      skip_ticks_for(start_grace_time)
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
      # The pid, for post_stop_command, before cleanup forgets it
      @stopping_pid = actual_pid
      pre_stop_process

      if monitor_children
        System.get_children(actual_pid).each do |child_pid|
          ProcessJournal.append_pid_to_journal(name, child_pid)
        end
      end

      if stop_command
        cmd = prepare_command(stop_command)
        logger.warning "Executing stop command: #{cmd}"

        with_timeout(stop_grace_time, "stop") do
          run_command(cmd, "Stop")
        end
        cleanup_process
      elsif stop_signals
        send_stop_signals_in_background(stop_signals)
      else
        logger.warning "Executing default stop command. Sending TERM signal to #{actual_pid}"
        signal_process("TERM")
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

        with_timeout(restart_grace_time, "restart") do
          run_command(cmd, "Restart")
        end

        skip_ticks_for(restart_grace_time)
      else
        logger.warning "No restart_command specified. Must stop and start to restart"
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
      post_stop_process
    end
  end
end
