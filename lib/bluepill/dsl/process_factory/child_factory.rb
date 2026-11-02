# frozen_string_literal: true

module Bluepill
  class ProcessFactory
    # Create the processes of the children that a process finds
    #
    # A process that monitors its children gets one, with the block that
    # configures each child. Process asks it for a child's process when it
    # finds a new child, long after the config loaded, so the factory
    # checks the block when it's made: it runs the block once, as for a
    # child whose pid isn't known yet, so actual_pid is nil, and fails on a
    # mistake. It runs the block again for each child it creates.
    #
    # @api private
    class ChildFactory
      # Create a factory of a process's children, and check their config
      #
      # @param [String] parent_name the name of the process whose children
      #   it creates
      # @param [Hash{Symbol => Object}] parent_attributes the process's
      #   attributes, of which the children get the CHILD_ATTRIBUTES
      # @param [Proc] child_process_block the block that configures each
      #   child
      #
      # @return [void]
      #
      # @raise [ConfigError] for a mistake in the children's config
      #
      # @api private
      def initialize(parent_name, parent_attributes, child_process_block)
        # An attribute the parent leaves unset keeps the Process default
        @attributes = parent_attributes.slice(*Process::Attributes::CHILD_ATTRIBUTES)
        @child_process_block = child_process_block
        validate!(parent_name)
      end

      # Create the process of a child that bluepill found
      #
      # The child gets its parent's grace times, the parent's user and
      # groups, so its commands run as the parent's do, and its state from
      # whether it's running.
      #
      # @param [String] name the child's name
      # @param [Integer] pid the child's pid
      # @param [Logger] logger the child's logger
      #
      # @return [Process] the child's process
      #
      # @api private
      def create_child_process(name, pid, logger)
        child = ProcessProxy.new(name, @attributes, @child_process_block, actual_pid: pid)
        process = child.to_process(logger:)
        process.determine_initial_state
        process
      end

      private

      # Run the block for a child whose pid isn't known, and check it
      #
      # The block must set a stop_command. Making the child's process also
      # makes its checks, which fail on a check or an option that bluepill
      # doesn't have.
      #
      # @param [String] parent_name the name of the children's parent
      #
      # @return [void]
      #
      # @raise [ConfigError] for a mistake in the children's config
      #
      # @api private
      def validate!(parent_name)
        child = ProcessProxy.new("<child of #{parent_name}>", @attributes, @child_process_block)
        raise ConfigError, "Config Error: You must specify a stop_command for the children of '#{parent_name}'" unless child.stop_command

        child.to_process
      end
    end
  end
end
