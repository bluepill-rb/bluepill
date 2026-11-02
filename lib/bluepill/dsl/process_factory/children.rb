module Bluepill
  class ProcessFactory
    # Create the processes of the children that a process's factory finds
    #
    # A process that monitors its children gets a factory of its own, with
    # the process block that configures each child. Process asks it for a
    # child's process when it finds a new child.
    #
    # @api private
    module Children
      # Create the process of a child that bluepill found
      #
      # The child gets its parent's grace times, the parent's user and groups,
      # so its commands run as the parent's do, and its state from whether
      # it's running.
      #
      # @param [String] name the child's name
      # @param [Integer] pid the child's pid
      # @param [Logger] logger the child's logger
      #
      # @return [Process] the child's process
      #
      # @api private
      def create_child_process(name, pid, logger)
        attributes = inherited_attributes
        attributes[:actual_pid] = pid
        attributes[:logger] = logger

        child = ProcessProxy.new(name, attributes, @process_block)
        validate_child_process! child
        process = child.to_process

        process.determine_initial_state
        process
      end

      protected

      # Return the attributes a child gets from its parent
      #
      # These are the grace times, user and groups that the parent sets.
      #
      # @return [Hash{Symbol => Object}] the attributes
      #
      # @api private
      def inherited_attributes
        attributes = {} #: Hash[Symbol, untyped]
        # A grace time the parent leaves unset keeps the Process default
        [:start_grace_time, :stop_grace_time, :restart_grace_time, :uid, :gid, :supplementary_groups].each do |a|
          attributes[a] = @attributes.fetch(a) if @attributes.key?(a)
        end
        attributes
      end

      # Exit unless a monitored child has a stop_command
      #
      # @param [ProcessProxy] child the child's proxy
      #
      # @return [void]
      #
      # @api private
      def validate_child_process!(child)
        return if child.attributes.key?(:stop_command)

        $stderr.puts "Config Error: Invalid child process monitor for #{child.name}"
        $stderr.puts "You must specify a stop command to monitor child processes."
        exit(6)
      end
    end
  end
end
