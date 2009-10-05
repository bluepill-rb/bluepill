module Bluepill
  class Controller
    attr_accessor :bp_dir, :sockets_dir, :pids_dir
    attr_accessor :applications
    
    def initialize(options = {})
      self.bp_dir = options['bp_dir'] || '/var/bluepill'
      self.sockets_dir = File.join(bp_dir, 'socks')
      self.pids_dir = File.join(bp_dir, 'pids')
      self.applications = Hash.new 
    end
    
    def list
      Dir[File.join(sockets_dir, "*.sock")].map{|x| File.basename(x, ".sock")}
    end
    
    # TODO
    def active_application
      obj = Struct.new(:grep_pattern)
      def obj.grep_pattern(query)
        bluepilld = 'bluepill\[[[:digit:]]+\]:[[:space:]]+'
        pattern = ["sample_app", query].join('|')
        [bluepilld, '\[.*',  Regexp.escape(pattern), '.*\]'].join
      end
      
      obj
    end
    
    def send_cmd(application, command)
      applications[application] ||= Application.new(application, {"bp_dir" => bp_dir})
      applications[application].send(command.to_sym)
    end
  end
end