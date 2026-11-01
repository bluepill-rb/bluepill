require 'bluepill/system'

module Bluepill
  # Remember the pids and process groups of the processes bluepill starts
  #
  # Each process has a pid journal and a process group journal, files in the
  # app's journal directory with one id a line. Before bluepill starts a
  # process, it kills whatever an earlier run left in that process's
  # journals.
  #
  # A pid can belong to another process by then: after a reboot, or once
  # pids wrap around. So each line also has when the process started, and
  # bluepill only kills a pid that still belongs to a process that started
  # then. A process group whose leader has exited is only killed if it was
  # journaled since the machine booted. Lines without a start time, from
  # bluepill 0.1 and earlier, are only trusted if the journal was written
  # since the machine booted.
  #
  # Each app has a journal directory of its own, so two apps with a process
  # of the same name don't share a journal. Bluepill 0.1 and earlier kept
  # every app's journals in one directory, and those are still read and
  # cleared, so upgrading doesn't leave their processes behind.
  #
  # @api private
  module ProcessJournal
    class << self
      # Return the logger the journal writes to
      #
      # @return [Logger] the first logger that was set
      #
      # @api private
      attr_reader :logger

      # Return the directory the app's journals are in
      #
      # @return [String] the app's directory in the journals directory
      #
      # @api private
      attr_reader :journal_base_dir

      # Return the directory every app's journals were in before 0.2
      #
      # @return [String] the journals directory under bluepill's base dir
      #
      # @api private
      attr_reader :legacy_journal_dir

      # Set the logger the journal writes to, unless it already has one
      #
      # Only the first logger is kept.
      #
      # @param [Logger] new_logger the logger to use
      #
      # @return [Logger] the logger
      #
      # @api private
      def logger=(new_logger)
        @logger ||= new_logger
      end

      # Set the app's journal directory from bluepill's base dir, and create it
      #
      # Only the first base dir and app are kept. The directories are made
      # world-writable so processes that run as other users can lock their
      # journals.
      #
      # @param [String] base_dir bluepill's base directory
      # @param [#to_s] app_name the app's name
      #
      # @return [void]
      #
      # @api private
      def setup(base_dir, app_name)
        @legacy_journal_dir ||= File.join(base_dir, 'journals')
        @journal_base_dir ||= File.join(@legacy_journal_dir, app_name.to_s)
        [@legacy_journal_dir, @journal_base_dir].each do |dir|
          FileUtils.mkdir_p(dir) unless File.exist?(dir)
          FileUtils.chmod(0o777, dir)
        end
      end
    end

    # Return whether a pid can't be journaled or signaled
    #
    # A pid of 1 or less would reach init, or a whole process group.
    #
    # @param [Integer, nil] pid the pid to check
    #
    # @return [Boolean] true unless pid is an Integer above 1
    #
    # @api private
    def self.skip_pid?(pid)
      !pid.is_a?(Integer) || pid <= 1
    end

    # Return whether a process group id can't be journaled or signaled
    #
    # @param [Integer, nil] pgid the process group id to check
    #
    # @return [Boolean] true unless pgid is an Integer above 1
    #
    # @api private
    def self.skip_pgid?(pgid)
      !pgid.is_a?(Integer) || pgid <= 1
    end

    # Run a block while holding a lock on a journal
    #
    # The lock is a directory, since making one is atomic on POSIX
    # filesystems and f.flock(File::LOCK_SH) is not available on all
    # platforms. It waits up to 10 seconds for another process's lock.
    #
    # @param [String] name the journal's file name
    #
    # @yield while holding the lock
    # @yieldreturn [Object] what the method returns
    #
    # @return [Object] what the block returns
    #
    # @raise [RuntimeError] if the lock is still held after 10 tries
    #
    # @api private
    def self.acquire_atomic_fs_lock(name)
      lock = "#{name}.lock"
      times = 0
      begin
        Dir.mkdir lock, 0o700
      rescue Errno::EEXIST
        times += 1
        if times < 10
          logger.debug("Waiting for lock #{lock}")
          sleep 1
          retry
        end
        logger.info("Timeout waiting for lock #{lock}")
        raise "Timeout waiting for lock #{lock}"
      end
      logger.debug("Acquired lock #{lock}")
      begin
        yield
      ensure
        clear_atomic_fs_lock(lock)
      end
    end

    # Remove the journal locks in the current directory
    #
    # @return [void]
    #
    # @api private
    def self.clear_all_atomic_fs_locks
      Dir['.*.lock'].each do |f|
        System.delete_if_exists(f) if File.directory?(f)
      end
    end

    # Return the path of a process's pid journal
    #
    # @param [String] journal_name the process's name
    # @param [String] dir the journal directory
    #
    # @return [String] the journal's path
    #
    # @api private
    def self.pid_journal_filename(journal_name, dir = journal_base_dir)
      File.join(dir, ".bluepill_pids_journal.#{journal_name}")
    end

    # Return the path of a process's process group journal
    #
    # @param [String] journal_name the process's name
    # @param [String] dir the journal directory
    #
    # @return [String] the journal's path
    #
    # @api private
    def self.pgid_journal_filename(journal_name, dir = journal_base_dir)
      File.join(dir, ".bluepill_pgids_journal.#{journal_name}")
    end

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
    def self.journal_entries(filename)
      File.readlines(filename).collect do |line|
        id, started = line.split
        [id.to_i, started && started.to_i]
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
    def self.journal_line(id)
      [id, System.started_at(id)].compact.join(' ')
    end

    # Return the valid pids in a pid journal
    #
    # @param [String] filename the journal's path
    #
    # @return [Array<Integer>] the pids, or none if there's no journal
    #
    # @api private
    def self.pid_journal(filename)
      logger.debug("pid journal file: #{filename}")
      result = journal_entries(filename).collect(&:first).reject { |pid| skip_pid?(pid) }
      logger.debug("pid journal = #{result.join(' ')}")
      result
    rescue Errno::ENOENT
      []
    end

    # Return the valid process group ids in a process group journal
    #
    # @param [String] filename the journal's path
    #
    # @return [Array<Integer>] the process group ids, or none if there's no
    #   journal
    #
    # @api private
    def self.pgid_journal(filename)
      logger.debug("pgid journal file: #{filename}")
      result = journal_entries(filename).collect(&:first).reject { |pgid| skip_pgid?(pgid) }
      logger.debug("pgid journal = #{result.join(' ')}")
      result
    rescue Errno::ENOENT
      []
    end

    # Release a journal lock, if it's there
    #
    # @param [String] name the lock's directory
    #
    # @return [void]
    #
    # @api private
    def self.clear_atomic_fs_lock(name)
      return unless File.directory?(name)

      Dir.rmdir(name)
      logger.debug("Cleared lock #{name}")
    end

    # Kill what every journal in the current directory lists
    #
    # @return [void]
    #
    # @api private
    def self.kill_all_from_all_journals
      pids = Dir['.bluepill_pids_journal.*'].collect { |p| p.sub(/\A\.bluepill_pids_journal\./, '') }
      pids.reject! { |p| p.end_with?('.lock') }
      pids.each do |journal_name|
        kill_all_from_journal(journal_name)
      end
    end

    # Kill the processes and process groups that a process's journals list
    #
    # @param [String] journal_name the process's name
    #
    # @return [void]
    #
    # @api private
    def self.kill_all_from_journal(journal_name)
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
    def self.kill_all_pgids_from_journal(journal_name)
      journal_dirs.each do |dir|
        filename = pgid_journal_filename(journal_name, dir)
        kill_all_from_journal_file(filename, pgid_journal(filename), 'process group', -1)
      end
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
    def self.kill_all_pids_from_journal(journal_name)
      journal_dirs.each do |dir|
        filename = pid_journal_filename(journal_name, dir)
        kill_all_from_journal_file(filename, pid_journal(filename), 'process', 1)
      end
    end

    # Return the directories a process's journals can be in
    #
    # @return [Array<String>] the app's, and then the one before 0.2
    #
    # @api private
    def self.journal_dirs
      [journal_base_dir, legacy_journal_dir]
    end

    # Kill the ids a journal lists, and then delete the journal
    #
    # Only kills the ids that still belong to what bluepill journaled (see
    # journaled_ids). Sends TERM, waits a second for any survivors, then
    # sends KILL to those still alive. A negative sign targets process groups
    # instead of pids.
    #
    # @param [String] filename the journal's path
    # @param [Array<Integer>] ids the pids or process group ids in it
    # @param [String] label what the ids are, for the log
    # @param [Integer] sign 1 for pids, or -1 for process groups
    #
    # @return [void]
    #
    # @api private
    def self.kill_all_from_journal_file(filename, ids, label, sign)
      if ids.empty?
        logger.debug('No previous process journal - Skipping cleanup')
        return
      end

      acquire_atomic_fs_lock(filename) do
        ids = journaled_ids(filename, ids, label)
        signal_journaled('TERM', ids, label, sign)
        survivors = ids.select { |id| System.pid_alive?(sign * id) }
        unless survivors.empty?
          sleep(1)
          survivors = survivors.select { |id| System.pid_alive?(sign * id) }
          signal_journaled('KILL', survivors, label, sign)
        end
        System.delete_if_exists(filename) # reset journal
        logger.debug('Journal cleanup completed')
      end
    end

    # Return the ids that still belong to what bluepill journaled
    #
    # An id whose process is running is kept only if that process started
    # when the journal says, give or take 2 seconds, since ps's elapsed time
    # is only accurate to a second. One whose process has exited (a process
    # group whose leader is gone) is kept only if it was journaled since the
    # machine booted, and so is one without a start time.
    #
    # @param [String] filename the journal's path
    # @param [Array<Integer>] ids the valid ids in it
    # @param [String] label what the ids are, for the log
    #
    # @return [Array<Integer>] the ids that are safe to signal, or none if
    #   the journal was cleared since its ids were read
    #
    # @api private
    def self.journaled_ids(filename, ids, label)
      # Journals only grow until they're cleared, under the lock this runs in
      return [] unless File.exist?(filename)

      started = Hash[journal_entries(filename)]
      boot = System.boot_time
      written = Integer(File.mtime(filename))
      ids.select do |id|
        now = System.started_at(id)
        journaled = started.fetch(id)
        ours = if now && journaled
                 (now - journaled).abs <= 2
               else
                 !boot.nil? && (journaled || written) >= boot - 2
               end
        logger.info("Skipping old #{label} #{id}, which isn't the one bluepill started") unless ours
        ours
      end
    end

    # Send a signal to each journaled id, and log what happened
    #
    # @param [String] signal TERM or KILL
    # @param [Array<Integer>] ids the pids or process group ids
    # @param [String] label what the ids are, for the log
    # @param [Integer] sign 1 for pids, or -1 for process groups
    #
    # @return [void]
    #
    # @api private
    def self.signal_journaled(signal, ids, label, sign)
      past, verb = signal.eql?('TERM') ? %w[Termed term] : %w[Killed kill]
      ids.each do |id|
        begin
          ::Process.kill(signal, sign * id)
          logger.info("#{past} old #{label} #{id}")
        rescue Errno::ESRCH
          logger.debug("Unable to #{verb} missing #{label} #{id}")
        end
      end
    end

    # Add a process group id to a process's journal, unless it's there
    #
    # @param [String] journal_name the process's name
    # @param [Integer, nil] pgid the process group id
    #
    # @return [void]
    #
    # @api private
    def self.append_pgid_to_journal(journal_name, pgid)
      if skip_pgid?(pgid)
        logger.debug("Skipping invalid pgid #{pgid} (class #{pgid.class})")
        return
      end
      # skip_pgid? made sure it's an Integer
      valid_pgid = pgid #: Integer

      filename = pgid_journal_filename(journal_name)
      acquire_atomic_fs_lock(filename) do
        if pgid_journal(filename).include?(pgid)
          logger.debug("Skipping duplicate pgid #{pgid} already in journal #{journal_name}")
        else
          logger.debug("Saving pgid #{pgid} to process journal #{journal_name}")
          File.open(filename, 'a+', 0o600) { |f| f.puts(journal_line(valid_pgid)) }
          logger.info("Saved pgid #{pgid} to journal #{journal_name}")
          logger.debug("Journal now = #{File.read(filename)}")
        end
      end
    end

    # Add a pid, and its process group id, to a process's journals
    #
    # @param [String] journal_name the process's name
    # @param [Integer, nil] pid the pid
    #
    # @return [void]
    #
    # @api private
    def self.append_pid_to_journal(journal_name, pid)
      if skip_pid?(pid)
        logger.debug("Skipping invalid pid #{pid} (class #{pid.class})")
        return
      end
      # skip_pid? made sure it's an Integer
      valid_pid = pid #: Integer
      begin
        append_pgid_to_journal(journal_name, ::Process.getpgid(valid_pid))
      rescue Errno::ESRCH
      end

      filename = pid_journal_filename(journal_name)
      acquire_atomic_fs_lock(filename) do
        if pid_journal(filename).include?(pid)
          logger.debug("Skipping duplicate pid #{pid} already in journal #{journal_name}")
        else
          logger.debug("Saving pid #{pid} to process journal #{journal_name}")
          File.open(filename, 'a+', 0o600) { |f| f.puts(journal_line(valid_pid)) }
          logger.info("Saved pid #{pid} to journal #{journal_name}")
          logger.debug("Journal now = #{File.read(filename)}")
        end
      end
    end
  end
end
