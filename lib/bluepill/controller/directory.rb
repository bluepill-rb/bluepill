# frozen_string_literal: true

module Bluepill
  class Controller
    # Find the daemons in the base directory, and clean up after dead ones
    #
    # Controller is the only class that includes it.
    #
    # @api private
    module Directory
      # Return the names of the applications with a daemon's socket
      #
      # @return [Array<String>]
      #
      # @api private
      def running_applications = base_directory.socket_names

      private

      # Remove the socket and pid file of each daemon that's not running
      #
      # @return [void]
      #
      # @api private
      def cleanup_bluepill_directory
        running_applications.each do |app|
          pid = pid_for(app)
          next if pid && System.pid_alive?(pid)

          System.delete_if_exists(base_directory.pid_file(app))
          System.delete_if_exists(base_directory.socket_file(app))
        end
      end

      # Return the pid in an application's pid file
      #
      # @param [String] app the application's name
      #
      # @return [Integer, false] the pid, or false without a valid one
      #
      # @api private
      def pid_for(app)
        # false, not nil, so quit says "bluepilld[false] not running"
        PidFile.read(base_directory.pid_file(app)) || false
      end

      # Create the sockets and pids directories
      #
      # @return [void]
      #
      # @api private
      def setup_dir_structure
        [base_directory.sockets_dir, base_directory.pids_dir].each do |dir|
          FileUtils.mkdir_p(dir)
        end
      end
    end
  end
end
