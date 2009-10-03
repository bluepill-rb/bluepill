module Bluepill
  class Controller
    attr_accessor :bp_dir, :sockets_dir, :pids_dir
    attr_accessor :applications, :sockets
    
    def initialize(options = {})
      bp_dir = options['bp_dir']
      sockets_dir = File.join(bp_dir, 'sockets')
      pids_dir = File.join(pids_dir, 'pids') 
    end
    
    def list
      Dir["*.sock"].map{|x| File.basename(x, ".sock")}
    end
    
    def send(application, command)
      sockets[application] ||= Bluepill::Socket.new(name, bp_dir)
      sockets[application].write(command + "\n")
      puts sockets[application].gets
    end
  end
end