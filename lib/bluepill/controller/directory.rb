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
        pid_file = File.join(pids_dir, "#{app}.pid")
        return false unless File.exist?(pid_file)

        # An empty or garbled pid file reads as 0, and signaling pid 0 would
        # hit the CLI's own process group
        pid = File.read(pid_file).to_i
        (pid > 0) ? pid : false
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
