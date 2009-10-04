require 'socket'

module Bluepill
  class Socket
    attr_accessor :name, :bp_dir, :socket
    
    def initialize(name, bp_dir)
      self.name = name
      self.bp_dir = bp_dir
      @isserver = false
    end

    def client
      self.socket = UNIXSocket.open(socket_name)
    end
    
    def server
      @isserver = true
      begin
        self.socket = UNIXServer.open(socket_name)
      rescue Errno::EADDRINUSE
        #if sock file has been created.  test to see if there is a server
        tmp_socket = UNIXSocket.open(socket_name) rescue nil
        if tmp_socket.nil?
          cleanup_server
        else
          raise Exception.new("Server is already running")
        end
      end
    end
    
    def cleanup
      File.delete(socket_name) if @isserver      
    end
    
    def socket_name
      @socket_name ||= File.join(bp_dir, 'socks', name + ".sock") 
    end
    
  end
end
 