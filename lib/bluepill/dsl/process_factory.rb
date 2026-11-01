module Bluepill
  class ProcessFactory
    attr_reader :attributes

    # Only the keys matter
    @@process_keys = {} #: Hash[Array[String?], nil]
    @@pid_files = {} #: Hash[String, nil]

    def initialize(attributes, process_block)
      @attributes = attributes
      @process_block = process_block
    end

    def create_process(name, pids_dir)
      default_pid_file = assign_default_pid_file(name, pids_dir)

      process = ProcessProxy.new(name, @attributes, @process_block)
      child_process_block = @attributes.delete(:child_process_block)
      @attributes[:child_process_factory] = ProcessFactory.new(@attributes, child_process_block) if @attributes[:monitor_children]

      validate_process! process
      warn_unless_pid_known(process, default_pid_file)
      process.to_process
    end

    def create_child_process(name, pid, logger)
      attributes = {} #: Hash[Symbol, untyped]
      # A grace time the parent leaves unset keeps the Process default
      [:start_grace_time, :stop_grace_time, :restart_grace_time].each do |a|
        attributes[a] = @attributes[a] if @attributes.key?(a)
      end
      attributes[:actual_pid] = pid
      attributes[:logger] = logger

      child = ProcessProxy.new(name, attributes, @process_block)
      validate_child_process! child
      process = child.to_process

      process.determine_initial_state
      process
    end

  protected

    def assign_default_pid_file(process_name, pids_dir)
      return if @attributes.key?(:pid_file)

      group_name = @attributes[:group]
      default_pid_name = [group_name, process_name].compact.join('_').gsub(/[^A-Za-z0-9_-]/, '_')
      @attributes[:pid_file] = File.join(pids_dir, "#{default_pid_name}.pid")
    end

    # The process shares its attributes hash with the factory
    def validate_process!(process)
      validate_unique_process!(process)
      validate_required_attributes!(process)
      validate_unique_pid_file!
      validate_stop_signals!
    end

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

    def validate_required_attributes!(process)
      return if attributes.key?(:start_command)

      config_error!("Config Error: You must specify a start_command for '#{process.name}'")
    end

    def validate_unique_pid_file!
      pid_key = attributes.fetch(:pid_file).strip
      config_error!("Config Error: You have two entries with the pid file: #{pid_key}") if @@pid_files.key?(pid_key)
      @@pid_files[pid_key] = nil
    end

    # Checks the more specific problems before the 'odd number' message
    def validate_stop_signals!
      stop_signals = attributes[:stop_signals]
      return if stop_signals.nil?

      stop_signals.each_with_index do |value, i|
        expected, label = i.even? ? [Symbol, 'a symbol (signal)'] : [Integer, 'a number (delay)']
        next if value.is_a?(expected)

        config_error!("Config Error: Invalid stop_signals!  Expected #{label} at position #{i} instead of '#{value}'.")
      end
      config_error!('Config Error: Invalid stop_signals!  Expected an odd number of elements.') unless stop_signals.size.odd?

      stop_grace_time = attributes[:stop_grace_time]
      delays = stop_signals.select.with_index { |_, i| i.odd? }
      return unless stop_grace_time.nil? || stop_grace_time <= delays.inject(0, :+)

      config_error!('Config Error: Stop_grace_time should be greater than the sum of stop_signals delays!')
    end

    # Bluepill only writes the default pid file for processes it daemonizes,
    # so it cannot find the pid of any other process that uses it
    def warn_unless_pid_known(process, default_pid_file)
      return if attributes[:daemonize] || attributes[:pid_command] || !attributes.fetch(:pid_file).eql?(default_pid_file)

      warning = "Config Warning: '#{process.name}' sets no daemonize, pid_file or pid_command, " \
                "so bluepill cannot find its pid unless start_command writes it to #{default_pid_file}. " \
                'Set daemonize = true if start_command runs in the foreground.'
      $stderr.puts warning
    end

    def config_error!(message)
      $stderr.puts message
      exit(6)
    end

    def validate_child_process!(child)
      return if child.attributes.key?(:stop_command)

      $stderr.puts "Config Error: Invalid child process monitor for #{child.name}"
      $stderr.puts 'You must specify a stop command to monitor child processes.'
      exit(6)
    end
  end
end
