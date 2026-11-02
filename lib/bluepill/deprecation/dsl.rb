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
      form = name.to_s
      if form.end_with?("!")
        warn([:attribute_bang, key], "bluepill 0.3.0 removes process.#{form}. Write process.#{key} = true, which 0.2 takes too.")
      elsif !form.end_with?("=")
        warn([:attribute_value, key], "bluepill 0.3.0 removes process.#{key} value. Write process.#{key} = value, which 0.2 takes too.")
      end
      return unless CHILD_ATTRIBUTES.include?(key)

      warn([:child_attribute, key], "bluepill 0.3.0 doesn't let a process block set #{key}. " \
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

      warn([:monitor_children_block, process_name], "bluepill 0.3.0 fails the config when monitor_children has no block, " \
                                                    "as for process '#{process_name}'. Give it a block that sets the children's stop_command.")
    end

    # Warn about a second check of the same name in a process
    #
    # Bluepill 0.2 keeps only the last of them, and 0.3.0 runs them all.
    #
    # @param [String] process_name the process's name
    # @param [Symbol] name the check's name
    #
    # @return [void]
    #
    # @api private
    def self.check_duplicate_check(process_name, name)
      warn([:duplicate_check, name], "process '#{process_name}' has two checks #{name.inspect}. Bluepill 0.2 runs only the last, " \
                                     "and 0.3.0 runs both. Remove the one you don't want.")
    end
  end
end
