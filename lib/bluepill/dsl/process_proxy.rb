# frozen_string_literal: true

require "bluepill/dsl/attributes"
require "bluepill/process/attributes"

module Bluepill
  # The self of a process block in a config file
  #
  # Each of the process's attributes is set with `name = value`, and read
  # back with `name`, which is nil until it's set. See
  # {Process::CONFIGURABLE_ATTRIBUTES} for the attributes a process has, and
  # `group` sets the group it's in.
  #
  # @example
  #   app.process('web') do |process|
  #     process.start_command = '/usr/bin/my_server'
  #     process.daemonize = true
  #     process.checks :mem_usage, every: 10.seconds, below: 100.megabytes
  #   end
  #
  # @api public
  class ProcessProxy
    include DSL::Attributes

    # monitor_children sets the two attributes it leaves out
    attribute(*(Process::Attributes::CONFIGURABLE_ATTRIBUTES - %i[monitor_children child_process_factory]), :group)

    # Return the process's name
    #
    # @return [String] the name
    #
    # @api private
    attr_reader :name

    # Return the block that monitor_children gave, to configure each child
    #
    # @return [Proc, nil] the block
    #
    # @api private
    attr_reader :child_process_block

    # Return the pid of the child that a monitor_children block configures
    #
    # It's nil when bluepill checks the block as the config loads, before
    # it has found any children.
    #
    # @example
    #   process.monitor_children do |child|
    #     child.stdout = "/var/log/child.#{child.actual_pid}.log"
    #   end
    #
    # @return [Integer, nil] the child's pid, or nil for a process
    #
    # @api public
    attr_reader :actual_pid

    # Create the proxy of a process, and run its block
    #
    # @param [String] process_name the process's name
    # @param [Hash{Symbol => Object}] attributes the attributes the process
    #   starts with, which the block can override
    # @param [Proc] process_block the block that configures the process
    # @param [Integer, nil] actual_pid the pid of the child that the block
    #   configures, or nil for a process
    #
    # @return [void]
    #
    # @api private
    def initialize(process_name, attributes, process_block, actual_pid: nil)
      @name = process_name
      # A copy, so the block leaves the attributes it was given as they were
      @attributes = attributes.dup
      @actual_pid = actual_pid
      @checks = []

      evaluate(&process_block)
    end

    # Add a check of the process, or a trigger such as :flapping
    #
    # A process can have more than one check of a kind, such as two :http
    # checks of different URLs.
    #
    # @example
    #   process.checks :cpu_usage, every: 10.seconds, below: 50, times: [3, 5]
    #   process.checks :flapping, times: 2, within: 30.seconds, retry_in: 7.seconds
    #
    # @param [Symbol] name the check's name, such as :mem_usage
    # @param [Hash{Symbol => Object}] options the check's options, such as
    #   :every, :below and :times
    #
    # @return [void]
    #
    # @api public
    def checks(name, **options)
      @checks << [name, options]
      nil
    end

    # Monitor the process's children too
    #
    # The block configures each child the way a process block configures a
    # process. It must set a stop_command. Bluepill runs it once as the
    # config loads, to check it, and then again for each child it finds.
    #
    # @example
    #   process.monitor_children do |child|
    #     child.stop_command = 'kill -QUIT {{PID}}'
    #     child.checks :mem_usage, every: 10.seconds, below: 200.megabytes
    #   end
    #
    # @yield [child] configures each child
    # @yieldparam [ProcessProxy] child the child's proxy, which is also self
    # @yieldreturn [void]
    #
    # @return [Proc] the block
    #
    # @raise [ConfigError] without a block
    #
    # @api public
    def monitor_children(&child_process_block)
      raise ConfigError, "monitor_children for process '#{@name}' needs a block that configures the children" unless child_process_block

      @child_process_block = child_process_block
    end

    # Create the process that the block described
    #
    # The group isn't an attribute of the process: the application adds
    # the process to it.
    #
    # @param [Hash{Symbol => Object}] options more of the process's options,
    #   such as its logger, or the factory of its children
    #
    # @return [Process] the process
    #
    # @api private
    def to_process(**options)
      Process.new(@name, @checks, actual_pid: @actual_pid, **attributes.except(:group), **options)
    end

    # Name the process, for an unknown attribute's error
    #
    # @return [String] the process's name
    #
    # @api private
    def attribute_owner = "process '#{@name}'"
  end
end
