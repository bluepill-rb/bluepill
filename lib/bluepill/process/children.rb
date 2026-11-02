# frozen_string_literal: true

module Bluepill
  class Process
    # Keeps a Process for each of a Process's children, when it monitors them
    #
    # @api private
    module Children
      # Return whether bluepill watches the process's children
      #
      # @return [Boolean]
      #
      # @api private
      def monitor_children? = !!monitor_children

      # Update the list of children from the tick's ps table
      #
      # Children that are no longer running are dropped, and a Process is made
      # for each new one, with the checks monitor_children gave.
      #
      # @return [void]
      #
      # @api private
      def refresh_children!
        # First prune the list of dead children
        @children.delete_if { |child| !child.process_running?(true) }

        # Add new found children to the list
        new_children_pids = System.get_children(actual_pid) - @children.collect(&:actual_pid)
        return if new_children_pids.empty?

        logger.info "Existing children: #{@children.collect(&:actual_pid).join(",")}. Got new children: #{new_children_pids} for #{actual_pid}"
        add_children(new_children_pids)
      end

      # Make a Process for each new child, and add it to the list
      #
      # @param [Array<Integer>] child_pids the new children's pids
      #
      # @return [void]
      #
      # @api private
      def add_children(child_pids)
        # Construct a new process wrapper for each new found children
        # monitor_children sets the factory
        factory = child_process_factory #: ProcessFactory
        child_pids.each do |child_pid|
          @children << new_child(factory, child_pid)
        end
      end

      # Make a Process for a child
      #
      # A process that bluepill daemonizes also has the child's pid added to
      # its journal.
      #
      # @param [ProcessFactory] factory the factory monitor_children set
      # @param [Integer] child_pid the child's pid
      #
      # @return [Process] the child's process wrapper
      #
      # @api private
      def new_child(factory, child_pid)
        journal.append(child_pid) if daemonize?
        child_name = "<child(pid:#{child_pid})>"
        factory.create_child_process(child_name, child_pid, logger.prefix_with(child_name))
      end
    end
  end
end
