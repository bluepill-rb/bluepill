require 'fileutils'
require 'bluepill/system'

module Bluepill
  # Run the bluepill CLI's commands, and send them to the daemon
  #
  # The CLI and the daemon talk over a socket of the application's in the
  # base directory.
  #
  # @api private
  class Controller
    # The shell command that tails a log file ($1) through grep -E ($2)
    #
    # The path and the pattern are the shell's arguments, so they're never
    # parsed as shell code, whatever characters they hold.
    TAIL_COMMAND = 'tail -n 100 -f "$1" | grep -E "$2"'.freeze

    # What the CLI says when the daemon runs another version of bluepill
    OUT_OF_DATE = 'The running version of your daemon seems to be out of date.'.freeze

    # What the CLI says to a daemon from before 0.1.7, which can't say
    # which version it runs
    UNKNOWN_VERSION = 'The running daemon is older than bluepill 0.1.7, so the CLI cannot check its version. ' \
                      'Run bluepill load again to replace it.'.freeze

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
      self.sockets_dir = File.join(base_dir, 'socks')
      self.pids_dir = File.join(base_dir, 'pids')

      setup_dir_structure
      cleanup_bluepill_directory
    end

    # Return the names of the applications with a daemon's socket
    #
    # @return [Array<String>]
    #
    # @api private
    def running_applications
      Dir[File.join(sockets_dir, '*.sock')].collect { |x| File.basename(x, '.sock') }
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
        pid = pid_for(application)
        if pid && System.pid_alive?(pid)
          ::Process.kill('TERM', pid)
          puts "Killing bluepilld[#{pid}]"
        else
          puts "bluepilld[#{pid}] not running"
        end
      when :log
        log_file_location = send_to_daemon(application, :log_file).to_s
        log_file_location = log_file.to_s if log_file_location.rstrip.empty?

        requested_pattern = args.first
        puts "Tailing log for #{requested_pattern}..."
        # The path and the pattern are the shell's arguments, not its code
        Kernel.exec('sh', '-c', TAIL_COMMAND, 'sh', log_file_location, grep_pattern(application, requested_pattern))
      when *Application::PROCESS_COMMANDS
        # these need to be sent to the daemon and the results printed out
        affected = send_to_daemon(application, command, *args)
        if affected.empty?
          puts 'No processes effected'
        else
          puts "Sent #{command} to:"
          affected.each do |process|
            puts "  #{process}"
          end
        end
      else
        $stderr.puts(format('Unknown command `%s` (or application `%s` has not been loaded yet)', command, command))
        exit(1)
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

      command = [command, *args].join(':')
      response = Socket.client_command(base_dir, application, command)
      if response.is_a?(Exception)
        $stderr.puts 'Received error from server:'
        $stderr.puts response.inspect
        # join flattens the backtrace and makes a missing one empty
        $stderr.puts [response.backtrace].join("\n")
        exit(8)
      else
        response
      end
    rescue Errno::ECONNREFUSED
      abort('Connection Refused: Server is not running')
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
      pattern = [application, query].compact.join(':')
      ['\[.*', Regexp.escape(pattern), '.*'].join
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
      pid > 0 ? pid : false
    end

    # Create the sockets and pids directories
    #
    # @return [void]
    #
    # @api private
    def setup_dir_structure
      [@sockets_dir, @pids_dir].each do |dir|
        FileUtils.mkdir_p(dir) unless File.exist?(dir)
      end
    end

    # Abort unless an application's daemon runs this version of bluepill
    #
    # A daemon answers with its version as a String. One from before 0.1.7
    # answers with its Version module, which Marshal loads as the CLI's own,
    # so it can't say which version it runs. The CLI warns about it and goes
    # on, as it did before, so upgrading the gem doesn't stop the CLI from
    # working with the daemon that's running.
    #
    # @param [String] application the application's name
    #
    # @return [void]
    #
    # @api private
    def verify_version!(application)
      version = Socket.client_command(base_dir, application, 'version')
      return if Version.to_s.eql?(version)

      if version.instance_of?(String)
        abort("#{OUT_OF_DATE}\nDaemon Version: #{version}, CLI Version: #{Version}")
      else
        $stderr.puts(UNKNOWN_VERSION)
      end
    rescue ArgumentError
      abort(OUT_OF_DATE)
    end
  end
end
