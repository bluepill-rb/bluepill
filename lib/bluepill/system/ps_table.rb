# frozen_string_literal: true

module Bluepill
  module System
    # A tick's table of processes, as ps listed them
    #
    # Each row is a process's ps fields, Strings in the order of the column
    # constants, and the rows are by pid. System.ps_axu makes one each tick,
    # and every watch of every process reads it.
    #
    # @api private
    class PsTable
      # The column of a process's pid
      #
      # @api private
      PID = 0

      # The column of a process's parent's pid
      #
      # @api private
      PPID = 1

      # The column of the percent of a CPU a process uses
      #
      # @api private
      PCPU = 2

      # The column of a process's resident memory, in kilobytes
      #
      # @api private
      RSS = 3

      # The column of how long a process has been running, [[dd-]hh:]mm:ss
      #
      # @api private
      ETIME = 4

      # The column of a process's command and its arguments
      #
      # @api private
      COMMAND = 5

      # Parse what ps printed into a table
      #
      # @param [String] output ps's output, a line per process
      #
      # @return [PsTable] the table of each process's ps fields
      #
      # @api private
      def self.parse(output)
        lines = output.split("\n")

        rows = {} #: Hash[Integer, Array[String]]
        lines.each do |line|
          # Split off the fields before the command, and keep the command
          # whole, as ps printed it
          row = line.split(" ", COMMAND + 1)
          row[COMMAND] ||= ""
          rows[row.fetch(PID).to_i] = row
        end
        new(rows)
      end

      # Return each process's ps fields, by pid
      #
      # @return [Hash{Integer => Array<String>}] the rows
      #
      # @api private
      attr_reader :rows

      # Make a table of rows
      #
      # @param [Hash{Integer => Array<String>}] rows each process's ps
      #   fields, by pid
      #
      # @return [undefined]
      #
      # @api private
      def initialize(rows)
        @rows = rows
      end

      # Return a process's ps fields
      #
      # @param [Integer, nil] pid the process's pid
      #
      # @return [Array<String>, nil] its fields, or nil if ps doesn't list it
      #
      # @api private
      def row(pid)
        @rows[pid]
      end

      # Return the pids of a process's children
      #
      # @param [Integer, nil] pid the process's pid
      #
      # @return [Array<Integer>] its children's pids, in ps's order, or
      #   NO_PIDS if it has none
      #
      # @api private
      def children(pid)
        children_by_parent.fetch(pid, NO_PIDS)
      end

      # Return the pids of a process's descendants
      #
      # The pid must be above 0. The ps header row parses as pid 0 with ppid
      # 0, so it's its own child, and pid 0's descendants never end.
      #
      # @param [Integer] pid the process's pid
      #
      # @return [Array<Integer>] its children's pids, followed by theirs
      #
      # @api private
      def descendants(pid)
        children = children(pid)
        # Most processes have no children, and they all share one empty array
        return children if children.empty?

        found = children.dup
        children.each { |child| found.concat(descendants(child)) }
        found
      end

      # Add up a column of some processes' rows
      #
      # @param [Array<Integer>] pids the processes' pids, any that ps doesn't
      #   list skipped
      # @param [Integer] column the column to add up, such as RSS
      # @param [Float] total what to add them to
      #
      # @return [Float] the total
      #
      # @api private
      def sum(pids, column, total = 0.0)
        pids.each do |pid|
          row = @rows[pid]
          total += row.fetch(column).to_f if row
        end
        total
      end

      private

      # Return the pids in the table by their parent's pid
      #
      # It's built the first time it's asked for, so finding a process's
      # descendants takes as long as there are descendants, not a pass over
      # the whole table for each one.
      #
      # @return [Hash{Integer => Array<Integer>}] each parent's children, in
      #   ps's order
      #
      # @api private
      def children_by_parent
        @children_by_parent ||= begin
          index = {} #: Hash[Integer, Array[Integer]]
          @rows.each_pair { |pid, row| (index[row.fetch(PPID).to_i] ||= []) << pid }
          index
        end
      end
    end
  end
end
