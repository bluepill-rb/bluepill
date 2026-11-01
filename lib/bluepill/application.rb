require 'thread'
require 'bluepill/system'
require 'bluepill/process_journal'

module Bluepill
  class Application
    PROCESS_COMMANDS = [:start, :stop, :restart, :unmonitor, :status].freeze

    attr_accessor :name, :logger, :base_dir, :socket, :pid_file, :kill_timeout, :groups, :work_queue, :pids_dir, :log_file

    def initialize(name, options = {})
      self.name = name

      @foreground   = options[:foreground]
      self.log_file = options[:log_file]
      # Only used for a non-root user, who has a home
      home = ENV['HOME'] #: String
      self.base_dir = ProcessJournal.base_dir = options[:base_dir] ||
        ENV['BLUEPILL_BASE_DIR'] ||
        (::Process.euid != 0 ? File.join(home, '.bluepill') : '/var/run/bluepill')
      self.pid_file = File.join(base_dir, 'pids', "#{self.name}.pid")
      self.pids_dir = File.join(base_dir, 'pids', self.name)
      self.kill_timeout = options[:kill_timeout] || 10

      self.groups = {}

      setup_signal_traps
      setup_logger_and_pids_dir

      @mutex = Mutex.new
    end

    def foreground?
      !!@foreground
    end

    def mutex(&block)
      @mutex.synchronize(&block)
    end

    def load
      start_server
    rescue StandardError => e
      $stderr.puts('Failed to start bluepill:')
      $stderr.puts(format('%s `%s`', e.class.name, e.message))
      $stderr.puts(e.backtrace)
      exit(5)
    end

    PROCESS_COMMANDS.each do |command|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{command}(group_name = nil, process_name = nil)
          self.send_to_process_or_group(:#{command}, group_name, process_name)
        end
      RUBY
    end

    def add_process(process, group_name = nil)
      group_name = group_name.to_s if group_name

      groups[group_name] ||= Group.new(group_name, logger: logger.prefix_with(group_name))
      groups[group_name].add_process(process)
    end

    def version
      Bluepill::Version
    end

  protected

    def send_to_process_or_group(method, group_name, process_name)
      if group_name.nil? && process_name.nil?
        groups.values.collect do |group|
          group.send(method)
        end.flatten
      elsif groups.key?(group_name)
        groups[group_name].send(method, process_name)
      else
        # they must be targeting just by process name, which may contain ':'
        process_name = [group_name, process_name].compact.join(':')
        groups.values.collect do |group|
          group.send(method, process_name)
        end.flatten
      end
    end

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
              # An empty line leaves command nil, so send raises an error for the client
              mutex { send(command, *args) } # steep:ignore ArgumentTypeMismatch
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

    def start_server
      kill_previous_bluepill
      ProcessJournal.kill_all_from_all_journals
      ProcessJournal.clear_all_atomic_fs_locks

      begin
        ::Process.setpgid(0, 0)
      rescue Errno::EPERM
      end

      Daemonize.daemonize unless foreground?

      logger.reopen

      $0 = "bluepilld: #{name}"

      groups.each_value(&:determine_initial_state)

      write_pid_file
      self.socket = Bluepill::Socket.server(base_dir, name)
      start_listener

      run
    end

    def run
      @running = true # set to false by signal trap
      while @running
        mutex do
          System.reset_data
          groups.each_value(&:tick)
        end
        sleep 1
      end
    end

    def cleanup
      ProcessJournal.kill_all_from_all_journals
      ProcessJournal.clear_all_atomic_fs_locks
      begin
        System.delete_if_exists(socket.path) if socket
      rescue IOError
      end
      System.delete_if_exists(pid_file)
    end

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

    # Bluepill opens its log file and creates its pids dir as the user that
    # runs it. The uid and gid in the config only apply to its processes.
    def setup_logger_and_pids_dir
      self.logger = ProcessJournal.logger = Bluepill::Logger.new(log_file: log_file, stdout: foreground?).prefix_with(name)
      setup_pids_dir
    rescue SystemCallError => e
      $stderr.puts("Failed to start bluepill: #{e.message}")
      message = 'The user running bluepill must be able to write to its log_file and base_dir. ' \
                'The uid and gid in the config only apply to the processes it monitors.'
      $stderr.puts(message)
      exit(5)
    end

    def setup_pids_dir
      FileUtils.mkdir_p(pids_dir) unless File.exist?(pids_dir)
      # we need everybody to be able to write to the pids_dir as processes managed by
      # bluepill will be writing to this dir after they've dropped privileges
      FileUtils.chmod(0o777, pids_dir)
    end

    def kill_previous_bluepill
      return unless File.exist?(pid_file)

      previous_pid = File.read(pid_file).to_i
      return unless System.pid_alive?(previous_pid)

      ::Process.kill(0, previous_pid)
      puts "Killing previous bluepilld[#{previous_pid}]"
      ::Process.kill(2, previous_pid)
    rescue StandardError => e
      $stderr.puts 'Encountered error trying to kill previous bluepill:'
      $stderr.puts "#{e.class}: #{e.message}"
      exit(4) unless e.is_a?(Errno::ESRCH)
    else
      kill_timeout.times do |_i|
        sleep 0.5
        break unless System.pid_alive?(previous_pid)
      end

      if System.pid_alive?(previous_pid)
        $stderr.puts "Previous bluepilld[#{previous_pid}] didn't die"
        exit(4)
      end
    end

    def write_pid_file
      File.open(pid_file, 'w') { |x| x.write(::Process.pid) }
    end
  end
end
