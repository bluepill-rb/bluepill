require 'fileutils'
require 'bluepill/system'

module Bluepill
  class Controller
    attr_accessor :base_dir, :log_file, :sockets_dir, :pids_dir

    def initialize(options = {})
      self.log_file = options[:log_file]
      self.base_dir = options[:base_dir]
      self.sockets_dir = File.join(base_dir, 'socks')
      self.pids_dir = File.join(base_dir, 'pids')

      setup_dir_structure
      cleanup_bluepill_directory
    end

    def running_applications
      Dir[File.join(sockets_dir, '*.sock')].collect { |x| File.basename(x, '.sock') }
    end

    def handle_command(application, command, *args)
      case command.to_sym
      when :status
        puts send_to_daemon(application, :status, *args)
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
      when :quit
        pid = pid_for(application)
        if System.pid_alive?(pid)
          ::Process.kill('TERM', pid)
          puts "Killing bluepilld[#{pid}]"
        else
          puts "bluepilld[#{pid}] not running"
        end
      when :log
        log_file_location = send_to_daemon(application, :log_file)
        log_file_location = log_file if log_file_location.to_s.strip.empty?

        requested_pattern = args.first
        grep_pattern = self.grep_pattern(application, requested_pattern)

        tail = "tail -n 100 -f #{log_file_location} | grep -E '#{grep_pattern}'"
        puts "Tailing log for #{requested_pattern}..."
        Kernel.exec(tail)
      else
        $stderr.puts(format('Unknown command `%s` (or application `%s` has not been loaded yet)', command, command))
        exit(1)
      end
    end

    def send_to_daemon(application, command, *args)
      verify_version!(application)

      command = ([command, *args]).join(':')
      response = Socket.client_command(base_dir, application, command)
      if response.is_a?(Exception)
        $stderr.puts 'Received error from server:'
        $stderr.puts response.inspect
        $stderr.puts response.backtrace.join("\n")
        exit(8)
      else
        response
      end

    rescue Errno::ECONNREFUSED
      abort('Connection Refused: Server is not running')
    end

    def grep_pattern(application, query = nil)
      pattern = [application, query].compact.join(':')
      ['\[.*', Regexp.escape(pattern), '.*'].compact.join
    end

  private

    def cleanup_bluepill_directory
      running_applications.each do |app|
        pid = pid_for(app)
        next if !pid
        next if pid || System.pid_alive?(pid)
        pid_file = File.join(pids_dir, "#{app}.pid")
        sock_file = File.join(sockets_dir, "#{app}.sock")
        System.delete_if_exists(pid_file)
        System.delete_if_exists(sock_file)
      end
    end

    def pid_for(app)
      pid_file = File.join(pids_dir, "#{app}.pid")
      File.exist?(pid_file) && File.read(pid_file).to_i
    end

    def setup_dir_structure
      [@sockets_dir, @pids_dir].each do |dir|
        FileUtils.mkdir_p(dir) unless File.exist?(dir)
      end
    end

    def verify_version!(application)
      version = Socket.client_command(base_dir, application, 'version')
      if version != Bluepill::Version
        abort("The running version of your daemon seems to be out of date.\nDaemon Version: #{version}, CLI Version: #{Bluepill::Version}")
      end
    rescue ArgumentError
      abort('The running version of your daemon seems to be out of date.')
    end
  end
end
