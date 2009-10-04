module Bluepill
  class Controller
    attr_accessor :bp_dir, :sockets_dir, :pids_dir
    attr_accessor :applications
    
    def initialize(options = {})
      bp_dir = options['bp_dir'] || '/var/bluepill'
      sockets_dir = File.join(bp_dir, 'socks')
      pids_dir = File.join(bp_dir, 'pids')
      self.applications = Hash.new 
    end
    
    def list
      Dir[File.join(sockets_dir, "*.sock")].map{|x| File.basename(x, ".sock")}
    end
    
    def send_cmd(application, command)
      applications[application] ||= Application.new(application, {"bp_dir" => bp_dir})
      applications[application].send(command.to_sym)
    end
  end
end