module Bluepill
  class Process
    # Carries out the commands a user gives a Process from the command line
    #
    # @api private
    module UserCommands
      # Carry out a command from the command line
      #
      # @param [String] cmd start, stop, restart or unmonitor
      #
      # @return [void]
      #
      # @api private
      def handle_user_command(cmd)
        case cmd
        when "start" then user_start
        when "stop" then user_stop
        when "restart" then user_restart
        when "unmonitor" then user_unmonitor
        end
      end

      # Start the process, unless it's already running
      #
      # @return [void]
      #
      # @api private
      def user_start
        if process_running?(true)
          logger.warning("Refusing to re-run start command on an already running process.")
        else
          dispatch!(:start, "user initiated")
        end
      end

      # Stop the process, and stop monitoring it
      #
      # @return [void]
      #
      # @api private
      def user_stop
        stop_process
        dispatch!(:unmonitor, "user initiated")
      end

      # Restart the process
      #
      # @return [void]
      #
      # @api private
      def user_restart
        # Through the state machine, like a check's restart, so the process
        # shows as restarting and post_start_command runs once it's up. A
        # state restart can't leave, such as unmonitored, restarts it directly.
        restart_process unless dispatch!(:restart, "user initiated")
      end

      # Stop monitoring the process
      #
      # @return [void]
      #
      # @api private
      def user_unmonitor
        # When the user issues an unmonitor cmd, reset any triggers so that
        # scheduled events gets cleared
        triggers.each(&:reset!)
        dispatch!(:unmonitor, "user initiated")
      end
    end
  end
end
