require 'thread'
require 'bluepill/system'
require 'bluepill/process_journal'

module Bluepill
  # The bluepill daemon for one application
  #
  # It holds the application's groups of processes, ticks them every
  # second, and answers the commands that the CLI sends over its socket.
  #
  # @api private
  class Application
    # The commands that act on a process or group, and that the CLI sends
    PROCESS_COMMANDS = [:start, :stop, :restart, :unmonitor, :status].freeze

    attr_accessor :name, :logger, :base_dir, :socket, :pid_file, :kill_timeout, :groups, :work_queue, :pids_dir, :log_file

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

    # @!attribute [rw] work_queue
    #   An attribute that bluepill doesn't use
    #
    #   @return [Object]
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
    # @param [Hash{Symbol => Object}] options :foreground, :log_file,
    #   :log_level, :base_dir and :kill_timeout
    #
    # @return [void]
    #
    # @api private
    def initialize(name, options = {})
      self.name = name

      @foreground   = options[:foreground]
      self.log_file = options[:log_file]
      @log_level    = options[:log_level]
      # Only used for a non-root user, who has a home
      home = ENV.fetch('HOME', nil) #: String
      self.base_dir = options[:base_dir] ||
                      ENV['BLUEPILL_BASE_DIR'] ||
                      (::Process.euid.zero? ? '/var/run/bluepill' : File.join(home, '.bluepill'))
      ProcessJournal.setup(base_dir, name)
      self.pid_file = File.join(base_dir, 'pids', "#{name}.pid")
      self.pids_dir = File.join(base_dir, 'pids', name)
      self.kill_timeout = options[:kill_timeout] || 10

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
    def foreground?
      !!@foreground
    end

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
    def mutex(&block)
      @mutex.synchronize(&block)
    end

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
    rescue StandardError => e
      $stderr.puts('Failed to start bluepill:')
      $stderr.puts(format('%s `%s`', e.class.name, e.message))
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
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        # def start(group_name = nil, process_name = nil)
        #   self.send_to_process_or_group(:start, group_name, process_name)
        # end

        def #{command}(group_name = nil, process_name = nil)
          self.send_to_process_or_group(:#{command}, group_name, process_name)
        end
      RUBY
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
    # @return [Module] the Version module
    #
    # @api private
    def version
      Version
    end

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
        groups.values.collect do |group|
          group.public_send(method)
        end.flatten
      elsif groups.key?(group_name)
        groups.fetch(group_name).public_send(method, process_name)
      else
        # they must be targeting just by process name, which may contain ':'
        process_name = [group_name, process_name].compact.join(':')
        groups.values.collect do |group|
          group.public_send(method, process_name)
        end.flatten
      end
    end

    # Start the thread that answers commands on the socket
    #
    # It kills the thread that a previous call started. Each command is a
    # line, such as start:group:process, and the answer is the command's
    # result, or the error it raised, marshaled.
    #
    # @return [Thread] the listener thread
    #
    # @api private
    def start_listener
      previous_thread = @listener_thread
      previous_thread.kill if previous_thread
      @listener_thread = Thread.new do
        loop do
          client = nil #: UNIXSocket?
          begin
            server = socket #: UNIXServer
            client = server.accept
            client.close_on_exec = true if client.respond_to?(:close_on_exec=)
            # The target is group:process and the process name may contain ':'
            command, *args = client.readline.strip.split(':', 3).reject(&:empty?)
            response = begin
              # An empty line leaves command nil, so public_send raises an error for the client
              mutex { public_send(command, *args) } # steep:ignore ArgumentTypeMismatch
            rescue StandardError => e
              e
            end
            client.write(Marshal.dump(response))
          rescue StandardError => e
            logger.err(format('Got exception in cmd listener: %s `%s`', e.class.name, e.message))
            Array(e.backtrace).each { |l| logger.err(l) }
          ensure
            begin
              # Ruby before 3.0 never counts branches in ensure as covered
              client && client.close
            rescue IOError
              # closed stream
            end
          end
        end
      end
    end

    # Start the daemon
    #
    # It stops a previous daemon for the application, clears journal locks
    # it left behind, daemonizes unless it runs in the foreground, opens the
    # socket, and runs until a signal stops it. Processes that are already
    # running, from their pid files, are monitored again, not restarted, so
    # bluepill can be upgraded without restarting them.
    #
    # @return [void]
    #
    # @api private
    def start_server
      kill_previous_bluepill
      ProcessJournal.clear_all_atomic_fs_locks

      begin
        ::Process.setpgid(0, 0)
      rescue Errno::EPERM
      end

      unless foreground?
        Daemonize.daemonize
        # Daemonizing ignores HUP, so trap it again to reopen the log on HUP
        setup_signal_traps
      end

      logger.reopen

      $0 = "bluepilld: #{name}"

      groups.each_value(&:determine_initial_state)

      write_pid_file
      self.socket = Socket.server(base_dir, name)
      start_listener

      run
    end

    # Tick every group once a second, until a signal stops the daemon
    #
    # @return [void]
    #
    # @api private
    def run
      @running = true # set to false by signal trap
      while @running
        mutex do
          System.reset_data
          groups.each_value(&:tick)
        end
        # Kernel.sleep, not sleep, so the specs can stand in for the clock
        Kernel.sleep(1)
      end
    end

    # Clear the app's journal locks, and remove the socket and pid file
    #
    # The processes keep running, so the next daemon monitors them again.
    #
    # @return [void]
    #
    # @api private
    def cleanup
      ProcessJournal.clear_all_atomic_fs_locks
      begin
        System.delete_if_exists(socket.path) if socket
      rescue IOError
      end
      System.delete_if_exists(pid_file)
    end

    # Trap TERM and INT to clean up and stop, and HUP to reopen the log
    #
    # @return [void]
    #
    # @api private
    def setup_signal_traps
      terminator = proc do
        puts 'Terminating...'
        cleanup
        @running = false
      end #: ^(Integer signal) -> void

      Signal.trap('TERM', &terminator)
      Signal.trap('INT', &terminator)

      Signal.trap('HUP') do
        logger.reopen if logger
      end
    end

    # Create the logger and the pids directory
    #
    # Bluepill opens its log file and creates its pids dir as the user that
    # runs it. The uid and gid in the config only apply to its processes.
    # It exits with status 5 if it can't.
    #
    # @return [void]
    #
    # @api private
    def setup_logger_and_pids_dir
      self.logger = ProcessJournal.logger = Logger.new(log_file: log_file, log_level: @log_level, stdout: foreground?).prefix_with(name)
      setup_pids_dir
    rescue SystemCallError => e
      $stderr.puts("Failed to start bluepill: #{e}")
      message = 'The user running bluepill must be able to write to its log_file and base_dir. ' \
                'The uid and gid in the config only apply to the processes it monitors.'
      $stderr.puts(message)
      exit(5)
    end

    # Create the pids directory, and let every user write to it
    #
    # @return [void]
    #
    # @api private
    def setup_pids_dir
      FileUtils.mkdir_p(pids_dir)
      # we need everybody to be able to write to the pids_dir as processes managed by
      # bluepill will be writing to this dir after they've dropped privileges
      FileUtils.chmod(0o777, pids_dir)
    end

    # Interrupt a daemon for this application that's still running
    #
    # It waits up to kill_timeout half seconds for the daemon to exit, and
    # exits with status 4 if it doesn't, or if signaling it fails.
    #
    # @return [void]
    #
    # @api private
    def kill_previous_bluepill
      return unless File.exist?(pid_file)

      # An empty or garbled pid file reads as 0, and signaling pid 0 would
      # interrupt bluepill's own process group
      previous_pid = File.read(pid_file).to_i
      return unless previous_pid > 0 && System.pid_alive?(previous_pid)

      ::Process.kill(0, previous_pid)
      puts "Killing previous bluepilld[#{previous_pid}]"
      ::Process.kill(2, previous_pid)
    rescue StandardError => e
      $stderr.puts 'Encountered error trying to kill previous bluepill:'
      $stderr.puts "#{e.class}: #{e}"
      exit(4) unless e.instance_of?(Errno::ESRCH)
    else
      kill_timeout.times do |_i|
        # Kernel.sleep, not sleep, so the specs can stand in for the clock
        Kernel.sleep(0.5)
        break unless System.pid_alive?(previous_pid)
      end

      if System.pid_alive?(previous_pid)
        $stderr.puts "Previous bluepilld[#{previous_pid}] didn't die"
        exit(4)
      end
    end

    # Write the daemon's pid to its pid file
    #
    # @return [void]
    #
    # @api private
    def write_pid_file
      File.write(pid_file, ::Process.pid.to_s)
    end
  end
end
