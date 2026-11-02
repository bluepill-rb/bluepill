require "bluepill/dsl/process_factory/children"

module Bluepill
  # Create the processes that a config file describes, and check them
  #
  # A factory turns a process block into a {Process}, after it checks the
  # config for mistakes, such as two processes with the same name or pid
  # file. A process that monitors its children gets a factory of its own for
  # them.
  #
  # @api private
  class ProcessFactory
    include Children

    # Return the attributes that each process starts with
    #
    # @return [Hash{Symbol => Object}] the attributes
    #
    # @api private
    attr_reader :attributes

    # Only the keys matter
    @@process_keys = {} #: Hash[Array[String?], nil]
    @@pid_files = {} #: Hash[String, nil]

    # Create a factory of processes
    #
    # @param [Hash{Symbol => Object}] attributes the attributes that each
    #   process starts with
    # @param [Proc] process_block the block that configures each process
    #
    # @return [void]
    #
    # @api private
    def initialize(attributes, process_block)
      @attributes = attributes
      @process_block = process_block
    end

    # Create a process from the factory's block, and check its config
    #
    # A process without a pid_file gets a default one in pids_dir.
    #
    # @param [String] name the process's name
    # @param [String] pids_dir the directory of the default pid file
    #
    # @return [Process] the process
    #
    # @api private
    def create_process(name, pids_dir)
      default_pid_file = assign_default_pid_file(name, pids_dir)

      process = ProcessProxy.new(name, @attributes, @process_block)
      child_process_block = @attributes.delete(:child_process_block)
      @attributes[:child_process_factory] = ProcessFactory.new(@attributes, child_process_block) if @attributes[:monitor_children]

      validate_process! process
      warn_unless_pid_known(process, default_pid_file)
      process.to_process
    end

    protected

    # Set the default pid file, unless the process sets its own
    #
    # @param [String] process_name the process's name
    # @param [String] pids_dir the directory of the pid file
    #
    # @return [String, nil] the default pid file, or nil when the process
    #   sets its own
    #
    # @api private
    def assign_default_pid_file(process_name, pids_dir)
      return if @attributes.key?(:pid_file)

      group_name = @attributes[:group]
      default_pid_name = [group_name, process_name].compact.join("_").gsub(/[^A-Za-z0-9_-]/, "_")
      @attributes[:pid_file] = File.join(pids_dir, "#{default_pid_name}.pid")
    end

    # Check a process's config, and exit on a mistake
    #
    # The process shares its attributes hash with the factory.
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_process!(process)
      validate_unique_process!(process)
      validate_required_attributes!(process)
      validate_unique_pid_file!
      validate_stop_signals!
    end

    # Exit if another process in the group has the same name
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_unique_process!(process)
      # A process name may contain ':', so the key keeps the parts apart.
      # Like Application#add_process, it treats Symbols and Strings alike.
      process_key = [attributes[:group], process.name].collect { |part| part && part.to_s }
      if @@process_keys.key?(process_key)
        message = "Config Error: You have two entries for the process name '#{process.name}'"
        message += " in the group '#{attributes.fetch(:group)}'" if attributes.key?(:group)
        config_error!(message)
      end
      @@process_keys[process_key] = nil
    end

    # Exit unless the process has a start_command
    #
    # @param [ProcessProxy] process the process's proxy
    #
    # @return [void]
    #
    # @api private
    def validate_required_attributes!(process)
      return if attributes.key?(:start_command)

      config_error!("Config Error: You must specify a start_command for '#{process.name}'")
    end

    # Exit if another process has the same pid file
    #
    # @return [void]
    #
    # @api private
    def validate_unique_pid_file!
      pid_key = attributes.fetch(:pid_file).strip
      config_error!("Config Error: You have two entries with the pid file: #{pid_key}") if @@pid_files.key?(pid_key)
      @@pid_files[pid_key] = nil
    end

    # Exit on a mistake in stop_signals
    #
    # The signals and delays must alternate, starting and ending with a
    # signal, and stop_grace_time must be longer than the delays.
    #
    # @return [void]
    #
    # @api private
    def validate_stop_signals!
      stop_signals = attributes[:stop_signals]
      return if stop_signals.nil?

      validate_stop_signal_order!(stop_signals)
      validate_stop_grace_time!(stop_signals)
    end

    # Exit unless stop_signals alternates signals and delays
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

    # Exit unless stop_grace_time is longer than the stop_signals delays
    #
    # @param [Array<Symbol, Integer>] stop_signals the signals and delays
    #
    # @return [void]
    #
    # @api private
    def validate_stop_grace_time!(stop_signals)
      stop_grace_time = attributes[:stop_grace_time]
      delays = stop_signals.select.with_index { |_, i| i.odd? }
      return unless stop_grace_time.nil? || stop_grace_time <= delays.inject(0, :+)

      config_error!("Config Error: Stop_grace_time should be greater than the sum of stop_signals delays!")
    end

    # Warn when bluepill can't find the process's pid
    #
    # Bluepill only writes the default pid file for processes it daemonizes,
    # so it cannot find the pid of any other process that uses it.
    #
    # @param [ProcessProxy] process the process's proxy
    # @param [String, nil] default_pid_file the default pid file, or nil when
    #   the process sets its own
    #
    # @return [void]
    #
    # @api private
    def warn_unless_pid_known(process, default_pid_file)
      return if attributes[:daemonize] || attributes[:pid_command] || !attributes.fetch(:pid_file).eql?(default_pid_file)

      warning = "Config Warning: '#{process.name}' sets no daemonize, pid_file or pid_command, " \
                "so bluepill cannot find its pid unless start_command writes it to #{default_pid_file}. " \
                "Set daemonize = true if start_command runs in the foreground."
      $stderr.puts warning
    end

    # Print a config error and exit with status 6
    #
    # @param [String] message the error
    #
    # @return [void] it never returns
    #
    # @api private
    def config_error!(message)
      $stderr.puts message
      exit(6)
    end
  end
end
