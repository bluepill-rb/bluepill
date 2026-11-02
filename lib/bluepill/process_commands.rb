# frozen_string_literal: true

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
    # @return [Integer] when ticks resume, from Clock.now
    #
    # @api private
    def start_process
      # An old stop signal thread would otherwise signal and clean up the new process
      clean_threads
      journal.kill_all # be sure nothing else is running from previous runs
      pre_start_process
      # ProcessFactory makes sure every process has a start command
      command = start_command #: String
      logger.warning "Executing start command: #{command}"
      run_start_command(command)

      skip_ticks_for(start_grace_time)
    end

    # Run the start command, as a daemon or for a self-daemonizing process
    #
    # A self-daemonizing process gets start_grace_time to finish, and then
    # on_start_timeout is dispatched.
    #
    # @param [String] command the start command
    #
    # @return [void]
    #
    # @api private
    def run_start_command(command)
      if daemonize?
        daemonize_process(command)
      else
        # This is a self-daemonizing process
        with_timeout(start_grace_time, on_start_timeout) do
          run_command(command, "Start")
        end
      end
    end

    # Run the start command as a daemon, and add its pid to the journal
    #
    # The children's pids go in the journal too.
    #
    # @param [String] command the start command
    #
    # @return [void]
    #
    # @api private
    def daemonize_process(command)
      # ProcessFactory gives every process that bluepill daemonizes a pid file
      file = pid_file #: String
      daemon_id = System.daemonize(command, command_options, pid_file: file, logger:)
      return unless daemon_id

      journal.append(daemon_id)
      # Only refresh_children! fills children, and only when monitoring them
      children.each do |child|
        journal.append(child.actual_pid)
      end
    end

    # Stop the process with its stop command, stop signals, or TERM
    #
    # The children's pids go in the journal first, so cleanup kills them too.
    # Stop signals are sent from a thread of their own, with their delays.
    # Ticks are skipped for stop_grace_time.
    #
    # @return [Integer] when ticks resume, from Clock.now
    #
    # @api private
    def stop_process
      # The pid, for post_stop_command, before cleanup forgets it
      @stopping_pid = actual_pid
      pre_stop_process
      journal_children if monitor_children
      send_stop
      skip_ticks_for(stop_grace_time)
    end

    # Add the pids of the process's children to its journal
    #
    # @return [void]
    #
    # @api private
    def journal_children
      System.get_children(actual_pid).each do |child_pid|
        journal.append(child_pid)
      end
    end

    # Run the stop command, send the stop signals, or send TERM
    #
    # @return [void]
    #
    # @api private
    def send_stop
      if stop_command
        run_stop_command(stop_command)
      elsif stop_signals
        send_stop_signals_in_background(stop_signals)
      else
        logger.warning "Executing default stop command. Sending TERM signal to #{actual_pid}"
        signal_process("TERM")
        cleanup_process
      end
    end

    # Run the stop command, and clean up after the process
    #
    # @param [String] command the stop command
    #
    # @return [void]
    #
    # @api private
    def run_stop_command(command)
      cmd = prepare_command(command)
      logger.warning "Executing stop command: #{cmd}"

      with_timeout(stop_grace_time, :stop) do
        run_command(cmd, "Stop")
      end
      cleanup_process
    end

    # Restart the process with its restart command, or by stopping and starting
    #
    # @return [Integer] when ticks resume, from Clock.now
    #
    # @api private
    def restart_process
      if restart_command
        run_restart_command(restart_command)
      else
        logger.warning "No restart_command specified. Must stop and start to restart"
        stop_process
        # Stop signals run in a thread. Wait for them, or start_process would
        # kill the stopping process from the journal before its delays are up.
        @threads.each(&:join)
        start_process
      end
    end

    # Run the restart command, and skip ticks for restart_grace_time
    #
    # @param [String] command the restart command
    #
    # @return [Integer] when ticks resume, from Clock.now
    #
    # @api private
    def run_restart_command(command)
      cmd = prepare_command(command)

      logger.warning "Executing restart command: #{cmd}"

      with_timeout(restart_grace_time, :restart) do
        run_command(cmd, "Restart")
      end

      skip_ticks_for(restart_grace_time)
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
      journal.kill_all # finish cleanup
      unlink_pid
      clear_pid
      post_stop_process
    end
  end
end
