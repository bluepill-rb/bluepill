require "bluepill/system"
require "bluepill/process_journal/cleanup"
require "bluepill/process_journal/lock"

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
    extend Cleanup
    extend Lock

    # What a journal holds: pids, or process group ids
    #
    # @!attribute name
    #   Return what the journal's log calls an id
    #
    #   @return [String] pid or pgid
    #
    #   @api private
    #
    # @!attribute label
    #   Return what the cleanup's log calls an id's process
    #
    #   @return [String] process or process group
    #
    #   @api private
    #
    # @!attribute file_tag
    #   Return what the journal's filename says it holds
    #
    #   @return [String] pids or pgids
    #
    #   @api private
    #
    # @!attribute sign
    #   Return what an id is multiplied by to signal it
    #
    #   A negative id signals the whole process group.
    #
    #   @return [Integer] 1 for pids, or -1 for process groups
    #
    #   @api private
    #
    # @api private
    Kind = Struct.new(:name, :label, :file_tag, :sign)

    # A pid journal's kind
    #
    # @api private
    PID = Kind.new("pid".freeze, "process".freeze, "pids".freeze, 1).freeze

    # A process group journal's kind
    #
    # @api private
    PGID = Kind.new("pgid".freeze, "process group".freeze, "pgids".freeze, -1).freeze

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
        @legacy_journal_dir ||= File.join(base_dir, "journals")
        @journal_base_dir ||= File.join(@legacy_journal_dir, app_name.to_s)
        [@legacy_journal_dir, @journal_base_dir].each do |dir|
          FileUtils.mkdir_p(dir)
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
      skip_id?(pid)
    end

    # Return whether a process group id can't be journaled or signaled
    #
    # @param [Integer, nil] pgid the process group id to check
    #
    # @return [Boolean] true unless pgid is an Integer above 1
    #
    # @api private
    def self.skip_pgid?(pgid)
      skip_id?(pgid)
    end

    # Return whether an id can't be journaled or signaled
    #
    # @param [Integer, nil] id the pid or process group id to check
    #
    # @return [Boolean] true unless id is an Integer above 1
    #
    # @api private
    def self.skip_id?(id)
      !id.is_a?(Integer) || id <= 1
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
      journal_filename(PID, journal_name, dir)
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
      journal_filename(PGID, journal_name, dir)
    end

    # Return the path of one of a process's journals
    #
    # @param [Kind] kind PID or PGID
    # @param [String] journal_name the process's name
    # @param [String] dir the journal directory
    #
    # @return [String] the journal's path
    #
    # @api private
    def self.journal_filename(kind, journal_name, dir = journal_base_dir)
      File.join(dir, ".bluepill_#{kind.file_tag}_journal.#{journal_name}")
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
      [id, System.started_at(id)].compact.join(" ")
    end

    # Return the valid pids in a pid journal
    #
    # @param [String] filename the journal's path
    #
    # @return [Array<Integer>] the pids, or none if there's no journal
    #
    # @api private
    def self.pid_journal(filename)
      journal_ids(PID, filename)
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
      journal_ids(PGID, filename)
    end

    # Return the valid ids in a journal
    #
    # @param [Kind] kind PID or PGID
    # @param [String] filename the journal's path
    #
    # @return [Array<Integer>] the ids, or none if there's no journal
    #
    # @api private
    def self.journal_ids(kind, filename)
      logger.debug("#{kind.name} journal file: #{filename}")
      result = journal_entries(filename).collect(&:first).reject { |id| skip_id?(id) }
      logger.debug("#{kind.name} journal = #{result.join(" ")}")
      result
    rescue Errno::ENOENT
      []
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
      append_to_journal(PGID, journal_name, pgid)
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
      append_to_journal(PID, journal_name, pid) { |valid_pid| append_process_group_to_journal(journal_name, valid_pid) }
    end

    # Add a process's process group id to the process's journal
    #
    # @param [String] journal_name the process's name
    # @param [Integer] pid the process's pid
    #
    # @return [void]
    #
    # @api private
    def self.append_process_group_to_journal(journal_name, pid)
      append_pgid_to_journal(journal_name, ::Process.getpgid(pid))
    rescue Errno::ESRCH
      # The process is gone, so it has no process group to journal
    end

    # Add an id to one of a process's journals, unless it's invalid
    #
    # @param [Kind] kind PID or PGID
    # @param [String] journal_name the process's name
    # @param [Integer, nil] id the pid or process group id
    #
    # @yield [id] once it's known to be valid, before it's journaled
    # @yieldparam [Integer] id the id
    #
    # @return [void]
    #
    # @api private
    def self.append_to_journal(kind, journal_name, id)
      if skip_id?(id)
        logger.debug("Skipping invalid #{kind.name} #{id} (class #{id.class})")
        return
      end
      # skip_id? made sure it's an Integer
      valid_id = id #: Integer
      yield valid_id if block_given?

      filename = journal_filename(kind, journal_name)
      write_to_journal(filename, journal_name, kind.name, valid_id) { journal_ids(kind, filename) }
    end

    # Add a line for an id to a journal, under its lock, unless it's there
    #
    # @param [String] filename the journal's path
    # @param [String] journal_name the process's name
    # @param [String] name what the id is, pid or pgid, for the log
    # @param [Integer] id the pid or process group id
    #
    # @yield under the lock, to read the journal
    # @yieldreturn [Array<Integer>] the ids already in the journal
    #
    # @return [void]
    #
    # @api private
    def self.write_to_journal(filename, journal_name, name, id)
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
