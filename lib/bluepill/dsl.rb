require 'ostruct'
module Bluepill
  def self.define_process_condition(name, &block)
    klass = Class.new(ProcessConditions::ProcessCondition, &block)
    ProcessConditions.const_set("#{name.to_s.camelcase}", klass)
  end
  
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
      
      def create_child_process_template
        if @child_process_block
          child_proxy = self.class.new
          # Children inherit some properties of the parent
          [:start_grace_time, :stop_grace_time, :restart_grace_time].each do |attribute|
            child_proxy.send("#{attribute}=", @attributes[attribute]) if @attributes.key?(attribute)
          end
          @child_process_block.call(child_proxy)
          validate_child_process(child_proxy)
          @attributes[:child_process_template] = child_proxy.to_process(nil)
        end
      end
      
      def monitor_children(&child_process_block)
        @child_process_block = child_process_block
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
      if RUBY_VERSION >= '1.9'
        class_variable_set(:@@app, app)
        class_variable_set(:@@process_proxy, process_proxy)
        class_variable_set(:@@process_keys, Hash.new) # because I don't want to require Set just for validations
        class_variable_set(:@@pid_files, Hash.new)
      else
        @@app = app
        @@process_proxy = process_proxy
        @@process_keys = Hash.new
        @@pid_files = Hash.new
      end
      attr_accessor :working_dir, :uid, :gid, :environment
      
      def validate_process(process, process_name)
        # validate uniqueness of group:process
        process_key = [process.attributes[:group], process_name].join(":")
        if @@process_keys.key?(process_key)
          $stderr.print "Config Error: You have two entries for the process name '#{process_name}'"
          $stderr.print " in the group '#{process.attributes[:group]}'" if process.attributes.key?(:group)
          $stderr.puts
          exit(6)
        else
          @@process_keys[process_key] = 0
        end
        
        # validate required attributes
        [:start_command].each do |required_attr|
          if !process.attributes.key?(required_attr)
            $stderr.puts "Config Error: You must specify a #{required_attr} for '#{process_name}'"
            exit(6)
          end
        end
        
        # validate uniqueness of pid files
        pid_key = process.pid_file.strip
        if @@pid_files.key?(pid_key)
          $stderr.puts "Config Error: You have two entries with the pid file: #{process.pid_file}"
          exit(6)
        else
          @@pid_files[pid_key] = 0
        end
      end
      
      def process(process_name, &process_block)
        process_proxy = @@process_proxy.new(process_name)
        process_block.call(process_proxy)
        process_proxy.create_child_process_template
        
        set_app_wide_attributes(process_proxy)
        
        assign_default_pid_file(process_proxy, process_name)
        
        validate_process(process_proxy, process_name)
        
        group = process_proxy.attributes.delete(:group)
        process = process_proxy.to_process(process_name)
        
        
        
        @@app.add_process(process, group)
      end
      
      def set_app_wide_attributes(process_proxy)
        [:working_dir, :uid, :gid, :environment].each do |attribute|
          unless process_proxy.attributes.key?(attribute)
            process_proxy.attributes[attribute] = self.send(attribute)
          end
        end
      end
      
      def assign_default_pid_file(process_proxy, process_name)
        unless process_proxy.attributes.key?(:pid_file)
          group_name = process_proxy.attributes["group"]
          default_pid_name = [group_name, process_name].compact.join('_').gsub(/[^A-Za-z0-9_\-]/, "_")
          process_proxy.pid_file = File.join(@@app.pids_dir, default_pid_name + ".pid")
        end
      end
    end
    
    yield(app_proxy.new)
    app.load
  end
end
