# frozen_string_literal: true

require "bluepill/system/ps_table"

module Bluepill
  module System
    # Raised when ps could not be run, so there is no data for this tick
    #
    # @api private
    class PsError < StandardError; end

    # Watches run in their own threads, so only let one of them run ps per tick
    #
    # @api private
    PS_MUTEX = Mutex.new

    # Run ps once a tick, and read its table of processes
    #
    # System extends this module, so these are System's module functions.
    # The table is memoized on System, so every watch of every process
    # reads the same one instead of forking a ps of its own.
    #
    # @api private
    module Ps
      # Forget the last tick's ps table, so ps runs again
      #
      # @return [void]
      #
      # @api private
      def reset_data
        @children_table = nil
        @ps_table = nil
      end

      # Return this tick's ps table, running ps the first time it's asked for
      #
      # When ps could not be run, the error is kept instead, and raised
      # again until the next tick.
      #
      # @return [PsTable] each process's ps fields
      #
      # @raise [PsError] if ps could not be run this tick
      #
      # @api private
      def ps_axu
        ps = PS_MUTEX.synchronize { @ps_table ||= read_ps_table }
        raise ps if ps.instance_of?(PsError)

        ps
      end

      # Run ps, and parse what it prints into a table
      #
      # @return [PsTable, PsError] each process's ps fields, or why ps could
      #   not be run
      #
      # @api private
      def read_ps_table
        # POSIX options, so this also works with System V ps on Solaris and SmartOS.
        # Use -A because -e shows the environment on FreeBSD and OpenBSD.
        PsTable.parse(`ps -Ao pid,ppid,pcpu,rss,etime,args`)
      rescue SystemCallError => e
        # Forking ps can fail, for example with ENOMEM or EAGAIN under memory pressure.
        # Keep the error so ps is not run again until the next tick.
        PsError.new("Could not run ps: #{e.class}: #{e}")
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

        # Each process asks every tick, so keep the table rather than take
        # PS_MUTEX again for each one
        (@children_table ||= ps_axu).descendants(parent_pid)
      rescue PsError
        NO_PIDS
      end
    end
  end
end
