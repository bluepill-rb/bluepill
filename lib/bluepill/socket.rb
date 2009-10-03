module Bluepill
  class Socket
    attr_accessor :name, :bp_dir, :socket
    
    def initialize(name, bp_dir)
      self.name = name
      self.bp_dir = bp_dir
      self.socket = UnixSocket.new(bp_dir)
    end
        
    def socket_name
      File.join(bp_dir, name + ".sock")
    end
    
    def gets(*args)
      self.socket.gets(args)
    end
    
    def write(*args)
      self.socket.write(*args)
    end
  end
end
 