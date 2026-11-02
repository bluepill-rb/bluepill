# frozen_string_literal: true

module Bluepill
  module Deprecation
    # The attributes that 0.3.0 doesn't let a process block set
    CHILD_ATTRIBUTES = %i[monitor_children child_process_factory].freeze

    # Warn about a way of setting a process attribute that 0.3.0 removes
    #
    # Bluepill 0.3.0 sets an attribute only with `name = value`, so
    # `name!` and `name value` fail, and a process block can't set
    # monitor_children or child_process_factory.
    #
    # @param [Symbol] name the method the pill file called, such as
    #   :daemonize!
    # @param [Symbol] key the attribute, such as :daemonize
    #
    # @return [void]
    #
    # @api private
    def self.check_attribute(name, key)
      if name.end_with?("!")
        warn("bluepill 0.3.0 removes process.#{name}. Write process.#{key} = true, which 0.2 takes too.")
      elsif !name.end_with?("=")
        warn("bluepill 0.3.0 removes process.#{key} value. Write process.#{key} = value, which 0.2 takes too.")
      end
      return unless CHILD_ATTRIBUTES.include?(key)

      warn("bluepill 0.3.0 doesn't let a process block set #{key}. " \
           "Call process.monitor_children with a block that configures the children, which 0.2 takes too.")
    end

    # Warn about monitor_children without a block, which 0.3.0 rejects
    #
    # @param [String] process_name the process's name
    # @param [Proc, nil] block the block that configures the children
    #
    # @return [void]
    #
    # @api private
    def self.check_monitor_children(process_name, block)
      return if block

      warn("bluepill 0.3.0 fails the config when monitor_children has no block, " \
           "as for process '#{process_name}'. Give it a block that sets the children's stop_command.")
    end

    # Warn about a monitor_children block that sets no stop_command
    #
    # @param [String] parent_name the parent process's name
    # @param [Hash{Symbol => Object}] attributes the attributes that the
    #   block set on a child
    #
    # @return [void]
    #
    # @api private
    def self.check_child_stop_command(parent_name, attributes)
      return if attributes.key?(:stop_command)

      warn("bluepill 0.3.0 fails the config when a monitor_children block sets no stop_command, " \
           "as for the children of '#{parent_name}', where 0.2 exits the daemon when it first finds a child. " \
           "Set the children's stop_command in the block.")
    end

    # Warn about a daemon older than 0.2.9, which 0.3.0's CLI refuses
    #
    # A daemon older than 0.2.9 answers the CLI with its Version module,
    # which Marshal loads as the CLI's own.
    #
    # @param [Module, String] version what the daemon answered
    #
    # @return [void]
    #
    # @api private
    def self.check_daemon_version(version)
      return if version.instance_of?(String)

      warn("this daemon runs a bluepill older than 0.2.9, which the CLI of bluepill 0.3.0 says is out of date. " \
           "Run bluepill load again, so the daemon runs this version.")
    end

    # The options that 0.3.0's Bluepill.application takes
    APPLICATION_OPTIONS = %i[foreground log_file log_level base_dir kill_timeout].freeze

    # Warn about options passed as a Hash, without **
    #
    # Bluepill 0.3.0 takes the options of Bluepill.application and checks
    # as keyword arguments, and Ruby 3 keeps a Hash passed without ** as a
    # positional argument, which fails. Ruby marks a Hash that a
    # ruby2_keywords method got as keywords, so the others are the ones
    # passed without **.
    #
    # @param [Array<Object>] args the arguments after the name
    # @param [String] call the call, as the message shows it, such as
    #   "process.checks :mem_usage"
    #
    # @return [void]
    #
    # @api private
    def self.check_keywords(args, call)
      positional = args.grep(Hash).reject { |options| Hash.ruby2_keywords_hash?(options) }
      return if positional.empty?

      warn("bluepill 0.3.0 takes the options of #{call} only as keyword arguments, " \
           "so options kept in a Hash fail unless they're passed with **. Write #{call}, **options, which 0.2 takes too.")
    end

    # Warn about an application option that 0.3.0 rejects
    #
    # @param [Hash{Symbol => Object}] options the application's options
    #
    # @return [void]
    #
    # @api private
    def self.check_application_options(options)
      (options.keys - APPLICATION_OPTIONS).each do |option|
        warn("bluepill 0.3.0 rejects the application option #{option}:, which 0.2 ignores. " \
             "Remove it, or fix its name.")
      end
    end

    # Warn about a second check of the same name in a process
    #
    # Bluepill 0.2 keeps only the last of them, and 0.3.0 runs them all.
    #
    # @param [Symbol] name the check's name
    #
    # @return [void]
    #
    # @api private
    def self.check_duplicate_check(name)
      warn("bluepill 0.3.0 runs every check of a process, so a process with two checks #{name.inspect} runs both, " \
           "where 0.2 runs only the last. Remove the one you don't want.")
    end
  end
end
