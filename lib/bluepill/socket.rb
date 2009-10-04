require 'socket'

module Bluepill
  class Socket
    attr_accessor :name, :bp_dir, :socket
    
    def initialize(name, bp_dir)
      self.name = name
      self.bp_dir = bp_dir
    end

    def client
      self.socket = UNIXSocket.open(socket_name)
    end
    
    def server
      self.socket = UNIXServer.open(socket_name)
    end
    
    def socket_name
      File.join(bp_dir, 'socks', name + ".sock")
    end
    
  end
end
 