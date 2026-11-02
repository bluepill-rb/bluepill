# frozen_string_literal: true

module Bluepill
  module ProcessJournal
    # Read and write the ids in a process's journals
    #
    # ProcessJournal extends it.
    #
    # @api private
    module Entries
      # Return a process's journals
      #
      # @param [#to_s] name the process's name
      #
      # @return [Journal]
      #
      # @api private
      def for(name) = Journal.new(name)

      # Return whether an id can't be journaled or signaled
      #
      # An id of 1 or less would reach init, or a whole process group.
      #
      # @param [Integer, nil] id the pid or process group id to check
      #
      # @return [Boolean] true unless id is an Integer above 1
      #
      # @api private
      def skip_id?(id) = !id.is_a?(Integer) || id <= 1

      # Return the ids in a journal, each with when its process started
      #
      # @param [String] filename the journal's path
      #
      # @return [Array<Array(Integer, Integer)>, Array<Array(Integer, nil)>]
      #   each id, with when its process started, or nil for a line from
      #   bluepill 0.1 and earlier, which has none
      #
      # @raise [Errno::ENOENT] if there's no journal
      #
      # @api private
      def journal_entries(filename)
        File.readlines(filename).collect do |line|
          id, started = line.split
          [id.to_i, started&.to_i]
        end
      end

      # Return a journal line for an id: the id, and when its process started
      #
      # @param [Integer] id a pid, or a process group id, whose leader's start
      #   is recorded
      #
      # @return [String] the line, without a start time if ps can't tell
      #
      # @api private
      def journal_line(id) = [id, System.started_at(id)].compact.join(" ")

      # Return the valid ids in a journal
      #
      # @param [Kind] kind PID or PGID
      # @param [String] filename the journal's path
      #
      # @return [Array<Integer>] the ids, or none if there's no journal
      #
      # @api private
      def journal_ids(kind, filename)
        logger.debug("#{kind.name} journal file: #{filename}")
        result = journal_entries(filename).collect(&:first).reject { |id| skip_id?(id) }
        logger.debug("#{kind.name} journal = #{result.join(" ")}")
        result
      rescue Errno::ENOENT
        []
      end

      # Add an id to one of a process's journals, unless it's invalid
      #
      # @param [Kind] kind PID or PGID
      # @param [#to_s] journal_name the process's name
      # @param [Integer, nil] id the pid or process group id
      #
      # @yield [id] once it's known to be valid, before it's journaled
      # @yieldparam [Integer] id the id
      #
      # @return [void]
      #
      # @api private
      def append(kind, journal_name, id)
        if skip_id?(id)
          logger.debug("Skipping invalid #{kind.name} #{id} (class #{id.class})")
          return
        end
        # skip_id? made sure it's an Integer
        valid_id = id #: Integer
        yield valid_id if block_given?

        filename = kind.filename(journal_base_dir, journal_name)
        write_to_journal(filename, journal_name, kind.name, valid_id) { journal_ids(kind, filename) }
      end

      # Add a line for an id to a journal, under its lock, unless it's there
      #
      # @param [String] filename the journal's path
      # @param [#to_s] journal_name the process's name
      # @param [String] name what the id is, pid or pgid, for the log
      # @param [Integer] id the pid or process group id
      #
      # @yield under the lock, to read the journal
      # @yieldreturn [Array<Integer>] the ids already in the journal
      #
      # @return [void]
      #
      # @api private
      def write_to_journal(filename, journal_name, name, id)
        acquire_atomic_fs_lock(filename) do
          if yield.include?(id)
            logger.debug("Skipping duplicate #{name} #{id} already in journal #{journal_name}")
          else
            logger.debug("Saving #{name} #{id} to process journal #{journal_name}")
            File.open(filename, "a+", 0o600) { |f| f.puts(journal_line(id)) }
            logger.info("Saved #{name} #{id} to journal #{journal_name}")
            logger.debug("Journal now = #{File.read(filename)}")
          end
        end
      end
    end
  end
end
