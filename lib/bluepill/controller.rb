require 'fileutils'

module Bluepill
  class Controller
    attr_accessor :base_dir, :sockets_dir, :pids_dir
    attr_accessor :applications
    
    def initialize(options = {})
      self.base_dir = options[:base_dir] || '/var/bluepill'
      self.sockets_dir = File.join(base_dir, 'socks')
      self.pids_dir = File.join(base_dir, 'pids')
      self.applications = Hash.new 
      setup_dir_structure
      cleanup
    end
    
    def list
      Dir[File.join(sockets_dir, "*.sock")].map{|x| File.basename(x, ".sock")}
    end
    
    def cleanup
      self.list.each do |app|
        pid = pid_for(app)
        if !pid || !alive?(pid)
          pid_file = File.join(self.pids_dir, "#{app}.pid")
          sock_file = File.join(self.sockets_dir, "#{app}.sock")
          File.unlink(pid_file) if File.exists?(pid_file)
          File.unlink(sock_file) if File.exists?(sock_file)
        end
      end
    end
    
    def send_cmd(application, command, *args)
      applications[application] ||= Application.new(application, {:base_dir => base_dir})
      applications[application].send(command.to_sym, *args.compact)
    end
    
    private
    
    def pid_for(app)
      pid_file = File.join(self.pids_dir, "#{app}.pid")
      File.exists?(pid_file) && File.read(pid_file).to_i
    end
    
    
    def alive?(pid)
      begin
        ::Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
    end
    
    def setup_dir_structure
      [@sockets_dir, @pids_dir].each do |dir|
        FileUtils.mkdir_p(dir) unless File.exists?(dir)
      end
    end
  end
end