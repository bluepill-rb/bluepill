require 'ostruct'
module Bluepill
  def self.application(app_name, options = {}, &block)
    app = Application.new(app_name.to_s, options, &block)
   
    process_proxy = Class.new do
      attr_reader :attributes, :watches
      def initialize
        @attributes = {}
        @watches = {}
      end
      
      def method_missing(name, *args)
        if args.size == 1 && name.to_s =~ /^(.*)=$/
          @attributes[$1.to_sym] = args.first
        elsif args.empty? && @attributes.key?(name.to_sym)
          @attributes[name.to_sym]
        else
          super
        end
      end
      
      def checks(name, options = {})
        @watches[name] = options
      end
    end
    
    app_proxy = Class.new do
      @@app = app
      @@process_proxy = process_proxy
      
      def process(process_name, &process_block)
        process_proxy = @@process_proxy.new
        process_block.call(process_proxy)
        
        group = process_proxy.attributes.delete(:group)
        
        process = Bluepill::Process.new(process_name, process_proxy.attributes)
        process_proxy.watches.each do |name, opts|
          if Bluepill::Trigger[name]
            process.add_trigger(name, opts)
          else
            process.add_watch(name, opts)
          end
        end
        
        @@app.add_process(process, group)
      end
    end
    
    yield(app_proxy.new)
    app.load
  end
end