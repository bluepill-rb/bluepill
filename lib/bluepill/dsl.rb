require 'ostruct'
module Bluepill
  def self.application(app_name, options = {}, &block)
    app = Application.new(app_name.to_s, options, &block)
    
    app_proxy = Class.new do
      @@app = app
      def process(process_name, &process_block)
        p = Process.new(process_name, &process_block)
        @@app.processes << p
      end
    end
    
    yield(app_proxy.new)
    
    app.processes.each {|p| p.dispatch!("start")}
    app.start
  end
end