# -*- encoding: utf-8 -*-
module Bluepill
  class ProcessFactory
    attr_reader :attributes

    @@process_keys = Hash.new
    @@pid_files = Hash.new

    def initialize(attributes, process_block)
      @attributes = attributes
      @process_block = process_block
    end

    def create_process(name, pids_dir)
      self.assign_default_pid_file(name, pids_dir)
      
      process = ProcessProxy.new(name, @attributes, @process_block)
      child_process_block = @attributes.delete(:child_process_block)
      @attributes[:child_process_factory] = ProcessFactory.new(@attributes, child_process_block) if @attributes[:monitor_children]
      
      self.validate_process! process
      process.to_process
    end

    def create_child_process(name, pid, logger)
      attributes = {}
      [:start_grace_time, :stop_grace_time, :restart_grace_time].each {|a| attributes[a] = @attributes[a]}
      attributes[:actual_pid] = pid
      attributes[:logger] = logger

      child = ProcessProxy.new(name, attributes, @process_block)
      self.validate_child_process! child
      process = child.to_process
      
      process.determine_initial_state
      process
    end

    protected

    def assign_default_pid_file(process_name, pids_dir)
      unless @attributes.key?(:pid_file)
        group_name = @attributes[:group]
        default_pid_name = [group_name, process_name].compact.join('_').gsub(/[^A-Za-z0-9_\-]/, "_")
        @attributes[:pid_file] = File.join(pids_dir, default_pid_name + ".pid")
      end
    end

    def validate_process!(process)
      # validate uniqueness of group:process
      process_key = [process.attributes[:group], process.name].join(":")
      if @@process_keys.key?(process_key)
        $stderr.print "Config Error: You have two entries for the process name '#{process.name}'"
        $stderr.print " in the group '#{process.attributes[:group]}'" if process.attributes.key?(:group)
        $stderr.puts
        exit(6)
      else
        @@process_keys[process_key] = 0
      end

      # validate required attributes
      [:start_command].each do |required_attr|
        if !process.attributes.key?(required_attr)
          $stderr.puts "Config Error: You must specify a #{required_attr} for '#{process.name}'"
          exit(6)
        end
      end

      # validate uniqueness of pid files
      pid_key = process.attributes[:pid_file].strip
      if @@pid_files.key?(pid_key)
        $stderr.puts "Config Error: You have two entries with the pid file: #{pid_key}"
        exit(6)
      else
        @@pid_files[pid_key] = 0
      end
    end

    def validate_child_process!(child)
      unless child.attributes.has_key?(:stop_command)
        $stderr.puts "Config Error: Invalid child process monitor for #{child.name}"
        $stderr.puts "You must specify a stop command to monitor child processes."
        exit(6)
      end
    end
  end
end
