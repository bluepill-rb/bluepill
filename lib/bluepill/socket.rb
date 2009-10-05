require 'socket'

module Bluepill
  class Socket
    attr_accessor :name, :base_dir, :socket
    
    def initialize(name, base_dir)
      self.name = name
      self.base_dir = base_dir
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
        puts "this sock file has already been created"
        tmp_socket = UNIXSocket.open(socket_name) rescue nil
        if tmp_socket.nil?
          cleanup
          retry
        else
          raise Exception.new("Server is already running")
        end
      end
    end
    
    def cleanup
      File.delete(socket_name) if @isserver      
    end
    
    def socket_name
      @socket_name ||= File.join(base_dir, 'socks', name + ".sock") 
    end
    
  end
end
 