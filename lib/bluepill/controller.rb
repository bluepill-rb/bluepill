require 'fileutils'

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
      Dir[File.join(sockets_dir, "*.sock")].map{|x| File.basename(x, ".sock")}
    end
    
    def handle_command(application, command, *args)
      case command.to_sym
      when *Application::PROCESS_COMMANDS
        # these need to be sent to the daemon and the results printed out
        affected = self.send_to_daemon(application, command, *args)
        if affected.empty?
          puts "No processes effected"
        else
          puts "Sent #{command} to:"
          affected.each do |process|
            puts "  #{process}"
          end
        end
      when :status
        puts self.send_to_daemon(application, :status, *args)
      when :quit
        pid = pid_for(application)
        if System.pid_alive?(pid)
          ::Process.kill("TERM", pid)
          puts "Killing bluepilld[#{pid}]"
        else
          puts "bluepilld[#{pid}] not running"
        end
      when :log
        log_file_location = self.send_to_daemon(application, :log_file)
        log_file_location = self.log_file if log_file_location.to_s.strip.empty?
        
        requested_pattern = args.first
        grep_pattern = self.grep_pattern(application, requested_pattern)
        
        tail = "tail -n 100 -f #{log_file_location} | grep -E '#{grep_pattern}'"
        puts "Tailing log for #{requested_pattern}..."
        Kernel.exec(tail)
      else
        $stderr.puts "Unknown command `%s` (or application `%s` has not been loaded yet)" % [command, command]
      end
    end
    
    def send_to_daemon(application, command, *args)

      begin
        Timeout::timeout(Socket::TIMEOUT) do
          buffer = ""
          socket = Socket.client(base_dir, application) # Something that should be interrupted if it takes too much time...
          socket.puts(([command] + args).join(":"))
          while line = socket.gets
            buffer << line
          end
          Marshal.load(buffer)
        end
      rescue Timeout::Error
        abort("Socket Timeout: Server may not be responding")
      rescue Errno::ECONNREFUSED
        abort("Connection Refused: Server is not running")
      end
    end
    
    def grep_pattern(application, query = nil)
      pattern = [application, query].compact.join(':')
      ['\[.*', Regexp.escape(pattern), '.*'].compact.join
    end
    private
    
    def cleanup_bluepill_directory
      self.running_applications.each do |app|
        pid = pid_for(app)
        if !pid || !System.pid_alive?(pid)
          pid_file = File.join(self.pids_dir, "#{app}.pid")
          sock_file = File.join(self.sockets_dir, "#{app}.sock")
          File.unlink(pid_file) if File.exists?(pid_file)
          File.unlink(sock_file) if File.exists?(sock_file)
        end
      end
    end
    
    def pid_for(app)
      pid_file = File.join(self.pids_dir, "#{app}.pid")
      File.exists?(pid_file) && File.read(pid_file).to_i
    end
    
    def setup_dir_structure
      [@sockets_dir, @pids_dir].each do |dir|
        FileUtils.mkdir_p(dir) unless File.exists?(dir)
      end
    end
  end
end