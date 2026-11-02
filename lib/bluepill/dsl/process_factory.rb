# frozen_string_literal: true

require "bluepill/dsl/process_factory/child_factory"
require "bluepill/dsl/process_factory/registry"

module Bluepill
  # Create the processes that a config file describes, and check them
  #
  # A factory turns a process block into a {Process}, after it checks the
  # config for mistakes, such as two processes with the same name or pid
  # file, which it looks up in the application's {Registry}. A process that
  # monitors its children gets a {ChildFactory} for them.
  #
  # @api private
  class ProcessFactory
    # Create a factory of processes
    #
    # @param [Hash{Symbol => Object}] attributes the attributes that each
    #   process starts with
    # @param [Proc] process_block the block that configures each process
    # @param [Registry] registry the process names and pid files that the
    #   application's other processes use
    #
    # @return [void]
    #
    # @api private
    def initialize(attributes, process_block, registry = Registry.new)
      @attributes = attributes
      @process_block = process_block
      @registry = registry
    end

    # Create a process from the factory's block, and check its config
    #
    # The process starts with the factory's attributes, and a default
    # pid_file in pids_dir unless they set one, and its block can override
    # them. It gets the application's logger, prefixed with its group's
    # name and its own, as its group's logger is with the group's name.
    #
    # @param [String] name the process's name
    # @param [String] pids_dir the directory of the default pid file
    # @param [Logger] logger the application's logger
    #
    # @return [Array(Process, Object)] the process, and the group that its
    #   block set, or nil for none
    #
    # @raise [ConfigError] for a mistake in the process's config
    #
    # @api private
    def create_process(name, pids_dir, logger:)
      default_pid_file = default_pid_file(name, pids_dir)
      process = ProcessProxy.new(name, {pid_file: default_pid_file}.merge(@attributes), @process_block)

      validate_process!(process)
      warn_unless_pid_known(process, default_pid_file)
      group = process.group
      process_logger = logger.prefix_with(group&.to_s).prefix_with(name)
      [process.to_process(logger: process_logger, **children_attributes(process)), group]
    end

    protected

    # Return the pid file of a process that sets none
    #
    # It's in pids_dir, named after the process and its group, if the
    # factory's attributes give one.
    #
    # @param [String] process_name the process's name
    # @param [String] pids_dir the directory of the pid file
    #
    # @return [String] the pid file
    #
    # @api private
    def default_pid_file(process_name, pids_dir)
      default_pid_name = [@attributes[:group], process_name].compact.join("_").gsub(/[^A-Za-z0-9_-]/, "_")
      File.join(pids_dir, "#{default_pid_name}.pid")
    end

    # Return the attributes that say whether a process monitors its children
    #
    # A process whose block calls monitor_children gets a factory of its
    # children.
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [Hash{Symbol => Object}] monitor_children and the
    #   child_process_factory, or nil for a process that doesn't monitor
    #   its children
    #
    # @raise [ConfigError] for a mistake in the children's config
    #
    # @api private
    def children_attributes(process)
      child_process_block = process.child_process_block
      factory = ChildFactory.new(process.name, process.attributes, child_process_block) if child_process_block
      {monitor_children: !factory.nil?, child_process_factory: factory}
    end

    # Check a process's config, and fail on a mistake
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_process!(process)
      validate_unique_process!(process)
      validate_required_attributes!(process)
      validate_unique_pid_file!(process)
      validate_stop_signals!(process)
      validate_on_start_timeout!(process)
    end

    # Fail if another process in the group has the same name
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_unique_process!(process)
      attributes = process.attributes
      return if @registry.add_process?(attributes[:group], process.name)

      message = "Config Error: You have two entries for the process name '#{process.name}'"
      message += " in the group '#{attributes.fetch(:group)}'" if attributes.key?(:group)
      config_error!(message)
    end

    # Fail unless the process has a start_command
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_required_attributes!(process)
      return if process.attributes.key?(:start_command)

      config_error!("Config Error: You must specify a start_command for '#{process.name}'")
    end

    # Fail if another process has the same pid file
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_unique_pid_file!(process)
      pid_file = process.attributes.fetch(:pid_file).strip
      return if @registry.add_pid_file?(pid_file)

      config_error!("Config Error: You have two entries with the pid file: #{pid_file}")
    end

    # Fail on a mistake in stop_signals
    #
    # The signals and delays must alternate, starting and ending with a
    # signal, and stop_grace_time must be longer than the delays.
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_stop_signals!(process)
      stop_signals = process.attributes[:stop_signals]
      return if stop_signals.nil?

      validate_stop_signal_order!(stop_signals)
      validate_stop_grace_time!(stop_signals, process.attributes[:stop_grace_time])
    end

    # Fail unless stop_signals alternates signals and delays
    #
    # The signals and delays must alternate, starting and ending with a
    # signal. Checks the more specific problems before the 'odd number'
    # message.
    #
    # @param [Array<Symbol, Integer>] stop_signals the signals and delays
    #
    # @return [void]
    #
    # @api private
    def validate_stop_signal_order!(stop_signals)
      stop_signals.each_with_index do |value, i|
        expected, label = i.even? ? [Symbol, "a symbol (signal)"] : [Integer, "a number (delay)"]
        next if value.is_a?(expected)

        config_error!("Config Error: Invalid stop_signals!  Expected #{label} at position #{i} instead of '#{value}'.")
      end
      config_error!("Config Error: Invalid stop_signals!  Expected an odd number of elements.") unless stop_signals.size.odd?
    end

    # Fail unless stop_grace_time is longer than the stop_signals delays
    #
    # @param [Array<Symbol, Integer>] stop_signals the signals and delays
    # @param [Integer, nil] stop_grace_time the process's stop_grace_time
    #
    # @return [void]
    #
    # @api private
    def validate_stop_grace_time!(stop_signals, stop_grace_time)
      delays = stop_signals.select.with_index { |_, i| i.odd? }
      return unless stop_grace_time.nil? || stop_grace_time <= delays.sum

      config_error!("Config Error: Stop_grace_time should be greater than the sum of stop_signals delays!")
    end

    # Fail unless on_start_timeout is an event of the state machine
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_on_start_timeout!(process)
      return unless process.attributes.key?(:on_start_timeout)

      events = Process::StateMachine::TRANSITIONS.keys
      event = process.on_start_timeout
      return if events.include?(event)

      config_error!("Config Error: on_start_timeout for '#{process.name}' must be one of #{events.collect(&:inspect).join(", ")}, not #{event.inspect}")
    end

    # Warn when bluepill can't find the process's pid
    #
    # Bluepill only writes the default pid file for processes it daemonizes,
    # so it cannot find the pid of any other process that uses it.
    #
    # @param [ProcessProxy] process the process's proxy
    # @param [String] default_pid_file the default pid file
    #
    # @return [void]
    #
    # @api private
    def warn_unless_pid_known(process, default_pid_file)
      attributes = process.attributes
      return if attributes[:daemonize] || attributes[:pid_command] || !process.pid_file.eql?(default_pid_file)

      warning = "Config Warning: '#{process.name}' sets no daemonize, pid_file or pid_command, " \
                "so bluepill cannot find its pid unless start_command writes it to #{default_pid_file}. " \
                "Set daemonize = true if start_command runs in the foreground."
      $stderr.puts warning
    end

    # Fail with a config error
    #
    # Bluepill.application prints its message and exits with status 6.
    #
    # @param [String] message the error
    #
    # @return [void] it never returns
    #
    # @raise [ConfigError] always
    #
    # @api private
    def config_error!(message) = raise(ConfigError, message)
  end
end
