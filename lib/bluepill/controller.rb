require "fileutils"
require "bluepill/system"

module Bluepill
  # Run the bluepill CLI's commands, and send them to the daemon
  #
  # The CLI and the daemon talk over a socket of the application's in the
  # base directory.
  #
  # @api private
  class Controller
    attr_accessor :base_dir, :log_file, :sockets_dir, :pids_dir

    # @!attribute [rw] base_dir
    #   The directory with the daemons' sockets and pid files
    #
    #   @return [String]
    #
    #   @api private

    # @!attribute [rw] log_file
    #   The log file to tail when the daemon doesn't name one
    #
    #   @return [String, nil]
    #
    #   @api private

    # @!attribute [rw] sockets_dir
    #   The directory with the daemons' sockets
    #
    #   @return [String]
    #
    #   @api private

    # @!attribute [rw] pids_dir
    #   The directory with the daemons' pid files
    #
    #   @return [String]
    #
    #   @api private

    # Create the controller, and clean up after daemons that died
    #
    # It creates the sockets and pids directories, and removes the socket
    # and pid file of each daemon that's no longer running.
    #
    # @param [Hash{Symbol => Object}] options :base_dir, and :log_file
    #
    # @return [void]
    #
    # @api private
    def initialize(options)
      self.log_file = options[:log_file]
      self.base_dir = options.fetch(:base_dir)
      self.sockets_dir = File.join(base_dir, "socks")
      self.pids_dir = File.join(base_dir, "pids")

      setup_dir_structure
      cleanup_bluepill_directory
    end

    # Return the names of the applications with a daemon's socket
    #
    # @return [Array<String>]
    #
    # @api private
    def running_applications
      Dir[File.join(sockets_dir, "*.sock")].collect { |x| File.basename(x, ".sock") }
    end

    # Run a CLI command and print what it did
    #
    # status prints the daemon's status, quit stops the daemon, log tails
    # the log for a process or group, and the PROCESS_COMMANDS go to the
    # daemon. It exits with status 1 for an unknown command.
    #
    # @param [String] application the application's name
    # @param [String, Symbol] command the command
    # @param [Array<String>] args the group or process, for example
    #
    # @return [void]
    #
    # @api private
    def handle_command(application, command, *args)
      case command.to_sym
      when :status
        puts send_to_daemon(application, :status, *args)
      when :quit
        quit_daemon(application)
      when :log
        tail_log(application, args.first)
      else
        send_process_command(application, command, *args)
      end
    end

    # Send a command to an application's daemon, and return its answer
    #
    # It first checks that the daemon runs this version of bluepill. It
    # prints an error that the daemon raised and exits with status 8, and
    # aborts if the daemon isn't running.
    #
    # @param [String] application the application's name
    # @param [String, Symbol] command the command
    # @param [Array<String>] args the command's arguments
    #
    # @return [Object] what the daemon answered
    #
    # @api private
    def send_to_daemon(application, command, *args)
      verify_version!(application)

      command = [command, *args].join(":")
      response = Socket.client_command(base_dir, application, command)
      exit_with_daemon_error(response) if response.is_a?(Exception)
      response
    rescue Errno::ECONNREFUSED
      abort("Connection Refused: Server is not running")
    end

    # Return the pattern that finds a process or group's lines in the log
    #
    # @param [String] application the application's name
    # @param [String, nil] query the process or group
    #
    # @return [String] an extended regular expression for grep
    #
    # @api private
    def grep_pattern(application, query = nil)
      pattern = [application, query].compact.join(":")
      ['\[.*', Regexp.escape(pattern), ".*"].join
    end

    private

    # Stop an application's daemon, if it's running
    #
    # @param [String] application the application's name
    #
    # @return [void]
    #
    # @api private
    def quit_daemon(application)
      pid = pid_for(application)
      if pid && System.pid_alive?(pid)
        ::Process.kill("TERM", pid)
        puts "Killing bluepilld[#{pid}]"
      else
        puts "bluepilld[#{pid}] not running"
      end
    end

    # Tail the daemon's log, showing only a process or group's lines
    #
    # It falls back to the controller's log_file when the daemon doesn't
    # name one, and replaces the CLI with tail.
    #
    # @param [String] application the application's name
    # @param [String, nil] requested_pattern the process or group
    #
    # @return [void]
    #
    # @api private
    def tail_log(application, requested_pattern)
      log_file_location = send_to_daemon(application, :log_file)
      log_file_location = log_file if log_file_location.to_s.rstrip.empty?

      pattern = grep_pattern(application, requested_pattern)

      tail = "tail -n 100 -f #{log_file_location} | grep -E '#{pattern}'"
      puts "Tailing log for #{requested_pattern}..."
      Kernel.exec(tail)
    end

    # Send one of the PROCESS_COMMANDS to the daemon and print what it did
    #
    # It exits with status 1 for any other command.
    #
    # @param [String] application the application's name
    # @param [String, Symbol] command the command
    # @param [Array<String>] args the group or process, for example
    #
    # @return [void]
    #
    # @api private
    def send_process_command(application, command, *args)
      unless Application::PROCESS_COMMANDS.include?(command.to_sym)
        $stderr.puts(format("Unknown command `%s` (or application `%s` has not been loaded yet)", command, command))
        exit(1)
      end

      # these need to be sent to the daemon and the results printed out
      print_affected(command, send_to_daemon(application, command, *args))
    end

    # Print the processes that a command affected
    #
    # @param [String, Symbol] command the command
    # @param [Array<String>] affected the processes, as group:process
    #
    # @return [void]
    #
    # @api private
    def print_affected(command, affected)
      if affected.empty?
        puts "No processes effected"
      else
        puts "Sent #{command} to:"
        affected.each do |process|
          puts "  #{process}"
        end
      end
    end

    # Print an error that the daemon raised, and exit with status 8
    #
    # @param [Exception] error the error
    #
    # @return [void]
    #
    # @api private
    def exit_with_daemon_error(error)
      $stderr.puts "Received error from server:"
      $stderr.puts error.inspect
      # join flattens the backtrace and makes a missing one empty
      $stderr.puts [error.backtrace].join("\n")
      exit(8)
    end

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

    # Abort unless an application's daemon runs this version of bluepill
    #
    # @param [String] application the application's name
    #
    # @return [void]
    #
    # @api private
    def verify_version!(application)
      version = Socket.client_command(base_dir, application, "version")
      abort("The running version of your daemon seems to be out of date.\nDaemon Version: #{version}, CLI Version: #{Version}") unless version.equal?(Version)
    rescue ArgumentError
      abort("The running version of your daemon seems to be out of date.")
    end
  end
end
