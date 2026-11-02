# frozen_string_literal: true

require "bluepill/system"
require "bluepill/process_journal"
require "bluepill/base_directory"
require "bluepill/pid_file"
require "bluepill/application/listener"
require "bluepill/application/lifecycle"
require "bluepill/application/previous_daemon"

module Bluepill
  # The bluepill daemon for one application
  #
  # It holds the application's groups of processes, ticks them every
  # second, and answers the commands that the CLI sends over its socket.
  #
  # @api private
  class Application
    include Listener
    include Lifecycle
    include PreviousDaemon

    # The commands that act on a process or group, and that the CLI sends
    PROCESS_COMMANDS = %i[start stop restart unmonitor status].freeze

    # The commands that the daemon answers on its socket, and no others
    #
    # The CLI sends the PROCESS_COMMANDS, version to check the daemon's
    # version, and log_file to find the log that it tails.
    DAEMON_COMMANDS = (PROCESS_COMMANDS + %i[version log_file]).freeze

    attr_accessor :name, :logger, :base_dir, :socket, :pid_file, :kill_timeout, :groups, :pids_dir, :log_file

    # @!attribute [rw] name
    #   The application's name, which names its socket and pid file
    #
    #   @return [String]
    #
    #   @api private

    # @!attribute [rw] logger
    #   The application's logger, prefixed with its name
    #
    #   @return [Logger]
    #
    #   @api private

    # @!attribute [rw] base_dir
    #   The directory with the daemon's sockets, pid files and journals
    #
    #   @return [String]
    #
    #   @api private

    # @!attribute [rw] socket
    #   The socket the daemon listens for commands on, once it's started
    #
    #   @return [UNIXServer, nil]
    #
    #   @api private

    # @!attribute [rw] pid_file
    #   The daemon's own pid file
    #
    #   @return [String]
    #
    #   @api private

    # @!attribute [rw] kill_timeout
    #   How many half seconds to wait for a previous daemon to exit
    #
    #   @return [Integer]
    #
    #   @api private

    # @!attribute [rw] groups
    #   The application's groups by name, with nil for processes in no group
    #
    #   @return [Hash{String, nil => Group}]
    #
    #   @api private

    # @!attribute [rw] pids_dir
    #   The directory with the pid files of the application's processes
    #
    #   @return [String]
    #
    #   @api private

    # @!attribute [rw] log_file
    #   The file the daemon logs to, or nil to log to syslog
    #
    #   @return [String, nil]
    #
    #   @api private

    # Create the daemon for an application
    #
    # It sets up signal traps, the logger and the pids directory. It exits
    # with status 5 if it can't write to its log file or base directory.
    #
    # @param [String] name the application's name
    # @param [Boolean] foreground whether to run in the foreground, rather
    #   than as a daemon
    # @param [String, nil] log_file the file to log to, or nil for syslog
    # @param [Symbol, String] log_level the least severe priority to log
    #   (debug, so everything, by default)
    # @param [String, nil] base_dir the directory for the socket and pid
    #   files, or nil for the default
    # @param [Numeric] kill_timeout how long to wait for an earlier daemon
    #   to exit, in half seconds
    #
    # @return [void]
    #
    # @api private
    def initialize(name, foreground: false, log_file: nil, log_level: :debug, base_dir: nil, kill_timeout: 10)
      self.name = name

      @foreground = foreground
      self.log_file = log_file
      @log_level = log_level
      setup_base_dir(base_dir)
      self.kill_timeout = kill_timeout

      self.groups = {}

      setup_signal_traps
      setup_logger_and_pids_dir

      @mutex = Mutex.new
    end

    # Return whether the daemon runs in the foreground
    #
    # @return [Boolean]
    #
    # @api private
    def foreground? = @foreground

    # Run a block while holding the daemon's lock
    #
    # Ticks and commands from the CLI hold it, so they never overlap.
    #
    # @yield the work to do while holding the lock
    # @yieldreturn [Object] what the block returns
    #
    # @return [Object] what the block returns
    #
    # @api private
    def synchronize(&block) = @mutex.synchronize(&block)

    # Start the daemon and monitor the application's processes
    #
    # It prints what went wrong, and exits with status 5, if the daemon
    # fails to start.
    #
    # @return [void]
    #
    # @api private
    def load
      start_server
    rescue => e
      $stderr.puts("Failed to start bluepill:")
      $stderr.puts(format("%s `%s`", e.class.name, e.message))
      $stderr.puts(e.backtrace)
      exit(5)
    end

    # @!method start(group_name = nil, process_name = nil)
    #   Start a process or group, or every process without either
    #
    #   @param [String, nil] group_name the group, or the process's name
    #     when no group has it
    #   @param [String, nil] process_name the process
    #
    #   @return [Array<String>] the affected processes, as group:process
    #
    #   @api private

    # @!method stop(group_name = nil, process_name = nil)
    #   Stop a process or group, or every process without either
    #
    #   @param [String, nil] group_name the group, or the process's name
    #     when no group has it
    #   @param [String, nil] process_name the process
    #
    #   @return [Array<String>] the affected processes, as group:process
    #
    #   @api private

    # @!method restart(group_name = nil, process_name = nil)
    #   Restart a process or group, or every process without either
    #
    #   @param [String, nil] group_name the group, or the process's name
    #     when no group has it
    #   @param [String, nil] process_name the process
    #
    #   @return [Array<String>] the affected processes, as group:process
    #
    #   @api private

    # @!method unmonitor(group_name = nil, process_name = nil)
    #   Stop monitoring a process or group, or every process without either
    #
    #   @param [String, nil] group_name the group, or the process's name
    #     when no group has it
    #   @param [String, nil] process_name the process
    #
    #   @return [Array<String>] the affected processes, as group:process
    #
    #   @api private

    # @!method status(group_name = nil, process_name = nil)
    #   Return the status of a process or group, or of every process
    #
    #   @param [String, nil] group_name the group, or the process's name
    #     when no group has it
    #   @param [String, nil] process_name the process
    #
    #   @return [Array<String>] the status lines
    #
    #   @api private

    # Define a method for each of the PROCESS_COMMANDS
    PROCESS_COMMANDS.each do |command|
      define_method(command) do |group_name = nil, process_name = nil|
        # @type self: Application
        send_to_process_or_group(command, group_name, process_name)
      end
    end

    # Add a process to a group, which is created if it's new
    #
    # @param [Process] process the process
    # @param [#to_s, nil] group_name the group, or nil for no group
    #
    # @return [Array<Process>] the group's processes
    #
    # @api private
    def add_process(process, group_name = nil)
      group_name = group_name.to_s if group_name
      process.app_name = name
      process.group_name = group_name

      groups[group_name] ||= Group.new(group_name, logger: logger.prefix_with(group_name))
      groups.fetch(group_name).add_process(process)
    end

    # Return the daemon's version, which the CLI checks against its own
    #
    # It's a String, since Marshal sends a module as only its name, which
    # the CLI would load as its own Version.
    #
    # @return [String] the version, such as "0.3.0"
    #
    # @api private
    def version = Version.to_s

    protected

    # Send a command to a process, a group, or every process
    #
    # @param [Symbol] method the command
    # @param [String, nil] group_name the group, or the start of a process
    #   name that contains a colon
    # @param [String, nil] process_name the process
    #
    # @return [Array<String>] what the groups returned, flattened
    #
    # @api private
    def send_to_process_or_group(method, group_name, process_name)
      if group_name.nil? && process_name.nil?
        send_to_groups(method)
      elsif groups.key?(group_name)
        groups.fetch(group_name).public_send(method, process_name)
      else
        # they must be targeting just by process name, which may contain ':'
        send_to_groups(method, [group_name, process_name].compact.join(":"))
      end
    end

    # Send a command to every group
    #
    # @param [Symbol] method the command
    # @param [Array<String>] args the process, or none for every process
    #
    # @return [Array<String>] what the groups returned, flattened
    #
    # @api private
    def send_to_groups(method, *args)
      groups.values.collect do |group|
        group.public_send(method, *args)
      end.flatten
    end

    # Set the base directory, and the journal and pid paths in it
    #
    # @param [String, nil] dir the base_dir option
    #
    # @return [void]
    #
    # @api private
    def setup_base_dir(dir)
      self.base_dir = dir || ENV["BLUEPILL_BASE_DIR"] || default_base_dir
      ProcessJournal.setup(base_dir, name)
      paths = BaseDirectory.new(base_dir)
      self.pid_file = paths.pid_file(name)
      self.pids_dir = paths.process_pids_dir(name)
    end

    # Return the base directory without an option or BLUEPILL_BASE_DIR
    #
    # @return [String] /var/run/bluepill for root, or ~/.bluepill
    #
    # @api private
    def default_base_dir
      # Only used for a non-root user, who has a home
      home = ENV.fetch("HOME", nil) #: String
      ::Process.euid.zero? ? "/var/run/bluepill" : File.join(home, ".bluepill")
    end
  end
end
