# frozen_string_literal: true

module Bluepill
  class Application
    # Stop a daemon for the application that's still running, before
    # starting a new one
    #
    # Application is the only class that includes it.
    #
    # @api private
    module PreviousDaemon
      protected

      # Interrupt a daemon for this application that's still running
      #
      # It waits up to kill_timeout half seconds for the daemon to exit, and
      # exits with status 4 if it doesn't, or if signaling it fails.
      #
      # @return [void]
      #
      # @api private
      def kill_previous_bluepill
        previous_pid = interrupt_previous_bluepill
        wait_for_previous_bluepill(previous_pid) if previous_pid
      end

      # Interrupt the previous daemon, if its pid file names a live one
      #
      # It exits with status 4 if signaling it fails, unless it's gone.
      #
      # @return [Integer, nil] the previous daemon's pid, or nil if it
      #   interrupted none, such as when it has just exited
      #
      # @api private
      def interrupt_previous_bluepill
        previous_pid = previous_bluepill_pid
        return unless previous_pid

        ::Process.kill(0, previous_pid)
        puts "Killing previous bluepilld[#{previous_pid}]"
        ::Process.kill(2, previous_pid)
        previous_pid
      rescue Errno::ESRCH
        # It exited after previous_bluepill_pid saw it alive, so there's
        # nothing to wait for
      rescue => e
        $stderr.puts "Encountered error trying to kill previous bluepill:\n#{e.class}: #{e}"
        exit(4)
      end

      # Return the pid of a previous daemon that's still running
      #
      # @return [Integer, nil] the pid in the pid file, or nil without a
      #   pid file or a live pid
      #
      # @api private
      def previous_bluepill_pid
        previous_pid = PidFile.read(pid_file)
        previous_pid if previous_pid && System.pid_alive?(previous_pid)
      end

      # Wait up to kill_timeout half seconds for the previous daemon to exit
      #
      # It exits with status 4 if the daemon is still running after.
      #
      # @param [Integer] previous_pid the previous daemon's pid
      #
      # @return [void]
      #
      # @api private
      def wait_for_previous_bluepill(previous_pid)
        kill_timeout.times do |_i|
          # Kernel.sleep, not sleep, so the specs can stand in for the clock
          Kernel.sleep(0.5)
          break unless System.pid_alive?(previous_pid)
        end

        return unless System.pid_alive?(previous_pid)

        $stderr.puts "Previous bluepilld[#{previous_pid}] didn't die"
        exit(4)
      end
    end
  end
end
