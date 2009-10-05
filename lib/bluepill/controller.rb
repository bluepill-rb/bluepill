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
    end
    
    def list
      Dir[File.join(sockets_dir, "*.sock")].map{|x| File.basename(x, ".sock")}
    end
    
    def send_cmd(application, command, *args)
      applications[application] ||= Application.new(application, {:base_dir => base_dir})
      applications[application].send(command.to_sym, *args.compact)
    end
    
    private
    
    def setup_dir_structure
      [@sockets_dir, @pids_dir].each do |dir|
        FileUtils.mkdir_p(dir) unless File.exists?(dir)
      end
    end
  end
end