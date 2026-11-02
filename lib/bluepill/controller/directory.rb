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
      def running_applications
        Dir[File.join(sockets_dir, "*.sock")].collect { |x| File.basename(x, ".sock") }
      end

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

          pid_file = File.join(pids_dir, "#{app}.pid")
          sock_file = File.join(sockets_dir, "#{app}.sock")
          System.delete_if_exists(pid_file)
          System.delete_if_exists(sock_file)
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
        PidFile.read(File.join(pids_dir, "#{app}.pid")) || false
      end

      # Create the sockets and pids directories
      #
      # @return [void]
      #
      # @api private
      def setup_dir_structure
        [@sockets_dir, @pids_dir].each do |dir|
          FileUtils.mkdir_p(dir)
        end
      end
    end
  end
end
