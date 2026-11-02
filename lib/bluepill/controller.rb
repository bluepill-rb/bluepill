# frozen_string_literal: true

require "fileutils"
require "bluepill/system"
require "bluepill/base_directory"
require "bluepill/pid_file"
require "bluepill/controller/directory"

module Bluepill
  # Run the bluepill CLI's commands, and send them to the daemon
  #
  # The CLI and the daemon talk over a socket of the application's in the
  # base directory.
  #
  # @api private
  class Controller
    include Directory

    # The shell command that tails a log file ($1) through grep -E ($2)
    #
    # The path and the pattern are the shell's arguments, so they're never
    # parsed as shell code, whatever characters they hold.
    TAIL_COMMAND = 'tail -n 100 -f "$1" | grep -E "$2"'

    # What the CLI says when the daemon runs another version of bluepill
    OUT_OF_DATE = "The running version of your daemon seems to be out of date."

    attr_accessor :base_dir, :log_file
    attr_reader :base_directory

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

    # @!attribute [r] base_directory
    #   The paths in the base directory
    #
    #   @return [BaseDirectory]
    #
    #   @api private

    # Create the controller, and clean up after daemons that died
    #
    # It creates the sockets and pids directories, and removes the socket
    # and pid file of each daemon that's no longer running.
    #
    # @param [String] base_dir the directory with the daemons' sockets and
    #   pid files
    # @param [String, nil] log_file the log file to tail when a daemon names
    #   none
    #
    # @return [void]
    #
    # @api private
    def initialize(base_dir:, log_file: nil)
      self.log_file = log_file
      self.base_dir = base_dir
      @base_directory = BaseDirectory.new(base_dir)

      setup_dir_structure
      cleanup_bluepill_directory
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
    # name one, and replaces the CLI with tail piped through grep.
    #
    # @param [String] application the application's name
    # @param [String, nil] requested_pattern the process or group
    #
    # @return [void]
    #
    # @api private
    def tail_log(application, requested_pattern)
      log_file_location = send_to_daemon(application, :log_file).to_s
      log_file_location = log_file.to_s if log_file_location.rstrip.empty?

      puts "Tailing log for #{requested_pattern}..."
      Kernel.exec("sh", "-c", TAIL_COMMAND, "sh", log_file_location, grep_pattern(application, requested_pattern))
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

    # Abort unless an application's daemon runs this version of bluepill
    #
    # A daemon older than 0.3.0 answers with its Version module, which
    # Marshal loads as the CLI's own, so it can't say which version it runs.
    #
    # @param [String] application the application's name
    #
    # @return [void]
    #
    # @api private
    def verify_version!(application)
      version = Socket.client_command(base_dir, application, "version")
      return if Version.to_s.eql?(version)

      abort(version.instance_of?(String) ? "#{OUT_OF_DATE}\nDaemon Version: #{version}, CLI Version: #{Version}" : OUT_OF_DATE)
    rescue ArgumentError
      abort(OUT_OF_DATE)
    end
  end
end
