require 'ostruct'
module Bluepill
  def self.application(app_name, options = {}, &block)
    app = Application.new(app_name.to_s, options, &block)
   
    process_proxy = Class.new do
      attr_reader :attributes, :watches
      def initialize(process_name = nil)
        @name = process_name
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
      
      def validate_child_process(child)
        unless child.attributes.has_key?(:stop_command)
          $stderr.puts "Config Error: Invalid child process monitor for #{@name}"
          $stderr.puts "You must specify a stop command to monitor child processes."
          exit(6)
        end
      end
      
      def monitor_children(&child_process_block)
        child_proxy = self.class.new
        
        # Children inherit some properties of the parent
        child_proxy.start_grace_time = @attributes[:start_grace_time]
        child_proxy.stop_grace_time = @attributes[:stop_grace_time]
        child_proxy.restart_grace_time = @attributes[:restart_grace_time]
        
        child_process_block.call(child_proxy)
        validate_child_process(child_proxy)
        
        @attributes[:child_process_template] = child_proxy.to_process(nil)
        # @attributes[:child_process_template].freeze
        @attributes[:monitor_children] = true
      end
      
      def to_process(process_name)
        process = Bluepill::Process.new(process_name, @attributes)
        @watches.each do |name, opts|
          if Bluepill::Trigger[name]
            process.add_trigger(name, opts)
          else
            process.add_watch(name, opts)
          end
        end
        process
      end
    end
    
    app_proxy = Class.new do
      @@app = app
      @@process_proxy = process_proxy
      @@process_names = Hash.new # becuase I don't want to require Set just for validations
      def validate_process(process, process_name)
        if @@process_names.key?(process_name)
          $stderr.puts "Config Error: You have two entries for the process name '#{process_name}'"
          exit(6)
        else
          @@process_names[process_name] = 0
        end
        
        [:start_command, :pid_file].each do |required_attr|
          if !process.attributes.key?(required_attr)
            $stderr.puts "Config Error: You must specify a #{required_attr} for '#{process_name}'"
            exit(6)
          end
        end
      end
      
      def process(process_name, &process_block)
        process_proxy = @@process_proxy.new(process_name)
        process_block.call(process_proxy)
        validate_process(process_proxy, process_name)
        
        group = process_proxy.attributes.delete(:group)        
        process = process_proxy.to_process(process_name)
        
        @@app.add_process(process, group)
      end
    end
    
    yield(app_proxy.new)
    app.load
  end
end