module Bluepill
  module System
    # Run ps once a tick, and read its table of processes
    #
    # System extends this module, so these are System's module functions.
    # The table is memoized on System, so every watch of every process
    # reads the same one instead of forking a ps of its own.
    #
    # @api private
    module Ps
      # Return what this tick has memoized
      #
      # @return [Hash{Symbol => Hash{Integer => Array<String>}, String}] the
      #   ps table, or ps's error, by name
      #
      # @api private
      def store
        @store ||= {}
      end

      # Forget what the last tick memoized, so ps runs again
      #
      # @return [void]
      #
      # @api private
      def reset_data
        @children_by_parent = nil
        store.clear
      end

      # Return this tick's ps table, running ps the first time it's asked for
      #
      # @return [Hash{Integer => Array<String>}] each process's ps fields, by
      #   pid, in the order of IDX_MAP
      #
      # @raise [PsError] if ps could not be run this tick
      #
      # @api private
      def ps_axu
        ps = PS_MUTEX.synchronize { store[:ps_axu] ||= read_ps_table }
        raise PsError, ps if ps.instance_of?(String)

        ps
      end

      # Run ps, and parse what it prints into a table
      #
      # @return [Hash{Integer => Array<String>}, String] each process's ps
      #   fields, by pid, or why ps could not be run
      #
      # @api private
      def read_ps_table
        table = {} #: ps_table
        command = IDX_MAP.fetch(:command)
        # POSIX options, so this also works with System V ps on Solaris and SmartOS.
        # Use -A because -e shows the environment on FreeBSD and OpenBSD.
        `ps -Ao pid,ppid,pcpu,rss,etime,args`.split("\n").each do |line|
          # Split off the fields before the command, and keep the command
          # whole, as ps printed it
          chunks = line.split(" ", command + 1)
          chunks[command] ||= ""
          table[chunks.fetch(IDX_MAP.fetch(:pid)).to_i] = chunks
        end
        table
      rescue SystemCallError => e
        # Forking ps can fail, for example with ENOMEM or EAGAIN under memory pressure.
        # Cache the message so ps is not run again until the next tick.
        "Could not run ps: #{e.class}: #{e}"
      end

      # Return the pids in this tick's ps table by their parent's pid
      #
      # It's built once per ps table, so finding a process's descendants
      # takes as long as there are descendants, not a pass over the whole
      # table for each one.
      #
      # @return [Hash{Integer => Array<Integer>}] each parent's children, in
      #   ps's order
      #
      # @raise [PsError] if ps could not be run
      #
      # @api private
      def children_by_parent
        @children_by_parent ||= begin
          index = {} #: Hash[Integer, Array[Integer]]
          ps_axu.each_pair { |pid, chunks| (index[chunks.fetch(IDX_MAP.fetch(:ppid)).to_i] ||= []) << pid }
          index
        end
      end

      # Return the pids of a process's descendants, from this tick's ps table
      #
      # @param [Integer, nil] parent_pid the process's pid
      #
      # @return [Array<Integer>] its children's pids, followed by theirs, or
      #   none if ps could not be run
      #
      # @api private
      def get_children(parent_pid)
        # A process that is still starting has no pid yet, and nil.to_i is 0.
        # The ps header row parses as pid 0 with ppid 0, so it would be its own
        # child and the recursion would never end.
        return NO_PIDS unless parent_pid.to_i > 0

        # Most processes have no children, and they all share one empty array
        children = children_by_parent.fetch(parent_pid) { return NO_PIDS }
        descendants = children.dup
        children.each { |pid| descendants.concat(get_children(pid)) }
        descendants
      rescue PsError
        NO_PIDS
      end
    end
  end
end
