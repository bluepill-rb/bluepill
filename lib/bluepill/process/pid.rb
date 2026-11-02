# frozen_string_literal: true

module Bluepill
  class Process
    # Finds, signals and forgets a Process's pid
    #
    # The pid comes from pid_command or the pid file. Every tick signals it
    # to see whether the process is still running.
    #
    # @api private
    module Pid
      # Return whether the process is running, and forget its pid if not
      #
      # The answer is kept for the rest of the tick.
      #
      # @param [Boolean] force whether to check again this tick
      #
      # @return [Boolean]
      #
      # @api private
      def process_running?(force = false)
        @process_running = nil if force # clear existing state if forced

        @process_running ||= signal_process(0)
        # the process isn't running, so we should clear the PID
        clear_pid unless @process_running
        @process_running #: bool
      end

      # Send a signal to the process
      #
      # A process without a pid isn't running, so it gets no signal and nothing
      # is logged. A failure is logged.
      #
      # @param [Integer, String, Symbol] code the signal, such as 0 or :term
      #
      # @return [Boolean] whether the signal was sent
      #
      # @api private
      def signal_process(code)
        code = code.to_s.upcase if code.is_a?(String) || code.instance_of?(Symbol)
        pid = actual_pid
        # Without a pid the process isn't running. That's expected before the
        # first start, and actual_pid already warns about a missing pid file.
        return false unless pid

        # kill with a pid of 0 or less signals a whole process group, which
        # could include bluepill itself, so only signal a real pid
        raise "invalid pid #{pid}" unless pid > 0

        ::Process.kill(code, pid)
        true
      rescue => e
        logger.err "Failed to signal process #{pid} with code #{code}: #{e}"
        false
      end

      # Return whether the pid is kept once it's read
      #
      # @return [Boolean]
      #
      # @api private
      def cache_actual_pid?
        !!@cache_actual_pid
      end

      # Return the process's pid, from pid_command or the pid file
      #
      # @return [Integer, nil] the pid, or nil if there's none yet
      #
      # @api private
      def actual_pid
        pid_command ? pid_from_command : pid_from_file
      end

      # Return the pid in the pid file, cached unless cache_actual_pid is false
      #
      # A missing pid file is logged as a warning.
      #
      # @return [Integer, nil] the pid, or nil without a pid file or a pid
      #
      # @api private
      def pid_from_file
        return @actual_pid if cache_actual_pid? && @actual_pid

        @actual_pid = if pid_file
          if File.exist?(pid_file)
            positive_pid(File.read(pid_file).to_i)
          else
            logger.warning("pid_file #{pid_file} does not exist or cannot be read")
            nil
          end
        end
      end

      # Return the pid that pid_command prints
      #
      # Output that isn't only digits gives no pid.
      #
      # @return [Integer, nil] the pid, or nil if the output isn't one
      #
      # @api private
      def pid_from_command
        # Output that is not just digits reads as nil, so as 0
        positive_pid(`#{pid_command}`.strip[/\A\d+\z/].to_i)
      end

      # Return the pid, unless it's 0 or less
      #
      # An empty or garbled pid file reads as 0, which is never a real process.
      #
      # @param [Integer] pid the pid that was read
      #
      # @return [Integer, nil] the pid, or nil if it's not a real one
      #
      # @api private
      def positive_pid(pid)
        pid if pid > 0
      end

      # Set the pid, and add it to the process's journal
      #
      # @param [Integer] pid the process's pid
      #
      # @return [void]
      #
      # @api private
      def actual_pid=(pid)
        ProcessJournal.append_pid_to_journal(name, pid) # be sure to always log the pid
        @actual_pid = pid
      end

      # Forget the process's pid
      #
      # The last pid is kept for notify_command, since a process that has died
      # has no pid by the time its state changes.
      #
      # @return [nil]
      #
      # @api private
      def clear_pid
        @last_pid = @actual_pid if @actual_pid
        @actual_pid = nil
      end

      # Delete the pid file, if there is one
      #
      # @return [void]
      #
      # @api private
      def unlink_pid
        System.delete_if_exists(pid_file)
      end
    end
  end
end
