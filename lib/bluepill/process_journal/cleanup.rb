# frozen_string_literal: true

module Bluepill
  module ProcessJournal
    # Kill what an earlier run left in a process's journals
    #
    # Before bluepill starts a process, it kills the processes and process
    # groups its journals list that are still the ones bluepill journaled,
    # and then clears the journals. ProcessJournal extends it.
    #
    # @api private
    module Cleanup
      # Kill the processes and process groups that a process's journals list
      #
      # @param [String] journal_name the process's name
      #
      # @return [void]
      #
      # @api private
      def kill_all_from_journal(journal_name)
        kill_all_pids_from_journal(journal_name)
        kill_all_pgids_from_journal(journal_name)
      end

      # Kill the process groups that a process's journals list
      #
      # That's the app's journal, and the one that bluepill 0.1 and earlier
      # shared between apps.
      #
      # @param [String] journal_name the process's name
      #
      # @return [void]
      #
      # @api private
      def kill_all_pgids_from_journal(journal_name)
        kill_all_ids_from_journal(PGID, journal_name)
      end

      # Kill the processes that a process's journals list
      #
      # That's the app's journal, and the one that bluepill 0.1 and earlier
      # shared between apps.
      #
      # @param [String] journal_name the process's name
      #
      # @return [void]
      #
      # @api private
      def kill_all_pids_from_journal(journal_name)
        kill_all_ids_from_journal(PID, journal_name)
      end

      # Kill the ids that one kind of a process's journals list
      #
      # That's the app's journal, and the one that bluepill 0.1 and earlier
      # shared between apps.
      #
      # @param [Kind] kind PID or PGID
      # @param [String] journal_name the process's name
      #
      # @return [void]
      #
      # @api private
      def kill_all_ids_from_journal(kind, journal_name)
        journal_dirs.each do |dir|
          filename = journal_filename(kind, journal_name, dir)
          kill_all_from_journal_file(filename, journal_ids(kind, filename), kind)
        end
      end

      # Return the directories a process's journals can be in
      #
      # @return [Array<String>] the app's, and then the one before 0.2
      #
      # @api private
      def journal_dirs
        [journal_base_dir, legacy_journal_dir]
      end

      # Kill the ids a journal lists, and then delete the journal
      #
      # Only kills the ids that still belong to what bluepill journaled (see
      # journaled_ids). Sends TERM, waits a second for any survivors, then
      # sends KILL to those still alive. The kind's sign makes process group
      # ids target their groups.
      #
      # @param [String] filename the journal's path
      # @param [Array<Integer>] ids the pids or process group ids in it
      # @param [Kind] kind PID or PGID
      #
      # @return [void]
      #
      # @api private
      def kill_all_from_journal_file(filename, ids, kind)
        if ids.empty?
          logger.debug("No previous process journal - Skipping cleanup")
          return
        end

        acquire_atomic_fs_lock(filename) do
          term_then_kill_journaled(journaled_ids(filename, ids, kind), kind)
          System.delete_if_exists(filename) # reset journal
          logger.debug("Journal cleanup completed")
        end
      end

      # Send TERM to journaled ids, and KILL to any still alive a second later
      #
      # It doesn't wait when every id exited on TERM.
      #
      # @param [Array<Integer>] ids the pids or process group ids
      # @param [Kind] kind PID or PGID
      #
      # @return [void]
      #
      # @api private
      def term_then_kill_journaled(ids, kind)
        signal_journaled("TERM", ids, kind)
        survivors = ids.select { |id| System.pid_alive?(kind.sign * id) }
        return if survivors.empty?

        sleep(1)
        survivors = survivors.select { |id| System.pid_alive?(kind.sign * id) }
        signal_journaled("KILL", survivors, kind)
      end

      # Return the ids that still belong to what bluepill journaled
      #
      # See same_journaled_process? for how it tells.
      #
      # @param [String] filename the journal's path
      # @param [Array<Integer>] ids the valid ids in it
      # @param [Kind] kind PID or PGID
      #
      # @return [Array<Integer>] the ids that are safe to signal, or none if
      #   the journal was cleared since its ids were read
      #
      # @api private
      def journaled_ids(filename, ids, kind)
        # Journals only grow until they're cleared, under the lock this runs in
        return [] unless File.exist?(filename)

        started = journal_entries(filename).to_h
        boot = System.boot_time
        written = Integer(File.mtime(filename))
        ids.select do |id|
          ours = same_journaled_process?(id, started.fetch(id), boot, written)
          logger.info("Skipping old #{kind.label} #{id}, which isn't the one bluepill started") unless ours
          ours
        end
      end

      # Return whether an id still belongs to the process bluepill journaled
      #
      # An id whose process is running is kept only if that process started
      # when the journal says, give or take 2 seconds, since ps's elapsed time
      # is only accurate to a second. One whose process has exited (a process
      # group whose leader is gone) is kept only if it was journaled since the
      # machine booted, and so is one without a start time.
      #
      # @param [Integer] id the pid or process group id
      # @param [Integer, nil] journaled when the journal says its process
      #   started, or nil for a line from bluepill 0.1 and earlier
      # @param [Integer, nil] boot when the machine booted, or nil if ps
      #   can't tell
      # @param [Integer] written when the journal was last written
      #
      # @return [Boolean] whether it's safe to signal
      #
      # @api private
      def same_journaled_process?(id, journaled, boot, written)
        now = System.started_at(id)
        if now && journaled
          (now - journaled).abs <= 2
        else
          !boot.nil? && (journaled || written) >= boot - 2
        end
      end

      # Send a signal to each journaled id, and log what happened
      #
      # @param [String] signal TERM or KILL
      # @param [Array<Integer>] ids the pids or process group ids
      # @param [Kind] kind PID or PGID
      #
      # @return [void]
      #
      # @api private
      def signal_journaled(signal, ids, kind)
        past, verb = signal.eql?("TERM") ? %w[Termed term] : %w[Killed kill]
        ids.each do |id|
          ::Process.kill(signal, kind.sign * id)
          logger.info("#{past} old #{kind.label} #{id}")
        rescue Errno::ESRCH
          logger.debug("Unable to #{verb} missing #{kind.label} #{id}")
        end
      end
    end
  end
end
