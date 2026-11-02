# frozen_string_literal: true

module Bluepill
  class Application
    # Start the daemon, run it until a signal stops it, and clean up after
    #
    # Application is the only class that includes it.
    #
    # @api private
    module Lifecycle
      protected

      # Start the daemon
      #
      # It creates the pids directory, stops a previous daemon for the
      # application, clears journal locks it left behind, daemonizes unless
      # it runs in the foreground, traps signals, opens the socket, and runs
      # until a signal stops it. Processes that are already running, from
      # their pid files, are monitored again, not restarted, so bluepill can
      # be upgraded without restarting them.
      #
      # @return [void]
      #
      # @raise [StartupError] if it can't create the pids directory
      # @raise [PreviousDaemonError] if it can't stop a previous daemon
      # @raise [AlreadyRunningError] if a daemon answers on the socket
      #
      # @api private
      def start_server
        setup_pids_dir
        kill_previous_bluepill
        ProcessJournal.clear_all_atomic_fs_locks
        become_process_group_leader
        # Trapped after daemonizing, which ignores HUP
        Daemonize.daemonize unless foreground?
        setup_signal_traps
        logger.reopen

        $0 = "bluepilld: #{name}"

        groups.each_value(&:determine_initial_state)
        serve
      end

      # Make the daemon its own process group's leader, if it may
      #
      # @return [void]
      #
      # @api private
      def become_process_group_leader
        ::Process.setpgid(0, 0)
      rescue Errno::EPERM
        # A session leader can't, and it already leads its process group
      end

      # Write the pid file, open the socket, and run the daemon
      #
      # @return [void]
      #
      # @api private
      def serve
        write_pid_file
        self.socket = Socket.server(base_dir, name)
        start_listener

        run
      end

      # Tick every group once a second, until a signal stops the daemon
      #
      # @return [void]
      #
      # @api private
      def run
        @running = true # set to false by signal trap
        while @running
          synchronize do
            System.reset_data
            groups.each_value(&:tick)
          end
          # Kernel.sleep, not sleep, so the specs can stand in for the clock
          Kernel.sleep(1)
        end
      end

      # Clear the app's journal locks, and remove the socket and pid file
      #
      # The processes keep running, so the next daemon monitors them again.
      #
      # @return [void]
      #
      # @api private
      def cleanup
        ProcessJournal.clear_all_atomic_fs_locks
        begin
          System.delete_if_exists(socket.path) if socket
        rescue IOError
          # A closed socket can't tell its path
        end
        System.delete_if_exists(pid_file)
      end

      # Trap TERM and INT to clean up and stop, and HUP to reopen the log
      #
      # @return [void]
      #
      # @api private
      def setup_signal_traps
        terminator = proc do
          puts "Terminating..."
          cleanup
          @running = false
        end #: ^(Integer signal) -> void

        Signal.trap("TERM", &terminator)
        Signal.trap("INT", &terminator)

        Signal.trap("HUP") do
          logger&.reopen
        end
      end

      # Create the logger, prefixed with the application's name
      #
      # Bluepill opens its log file as the user that runs it.
      #
      # @return [void]
      #
      # @raise [StartupError] if it can't open the log file
      #
      # @api private
      def setup_logger
        self.logger = ProcessJournal.logger = Logger.new(log_file:, log_level: @log_level, stdout: foreground?).prefix_with(name)
      rescue SystemCallError => e
        raise unwritable(e)
      end

      # Create the pids directory, and let every user write to it
      #
      # Bluepill creates it as the user that runs it.
      #
      # @return [void]
      #
      # @raise [StartupError] if it can't
      #
      # @api private
      def setup_pids_dir
        FileUtils.mkdir_p(pids_dir)
        # we need everybody to be able to write to the pids_dir as processes managed by
        # bluepill will be writing to this dir after they've dropped privileges
        FileUtils.chmod(0o777, pids_dir)
      rescue SystemCallError => e
        raise unwritable(e)
      end

      # Return the error for a file that bluepill can't write to
      #
      # @param [SystemCallError] error what writing to it raised
      #
      # @return [StartupError] the error, which says the uid and gid in the
      #   config only apply to the processes bluepill monitors
      #
      # @api private
      def unwritable(error)
        StartupError.new(
          "Failed to start bluepill: #{error}\n" \
          "The user running bluepill must be able to write to its log_file and base_dir. " \
          "The uid and gid in the config only apply to the processes it monitors."
        )
      end

      # Write the daemon's pid to its pid file
      #
      # @return [void]
      #
      # @api private
      def write_pid_file = File.write(pid_file, ::Process.pid.to_s)
    end
  end
end
