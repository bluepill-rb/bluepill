require 'bluepill/system'

module Bluepill
  module ProcessJournal
  module_function

    class << self
      attr_reader :logger, :journal_base_dir

      def logger=(new_logger)
        @logger ||= new_logger
      end

      def base_dir=(base_dir)
        @journal_base_dir ||= File.join(base_dir, 'journals')
        FileUtils.mkdir_p(@journal_base_dir) unless File.exist?(@journal_base_dir)
        FileUtils.chmod(0o777, @journal_base_dir)
      end
    end

    def skip_pid?(pid)
      !pid.is_a?(Integer) || pid <= 1
    end

    def skip_pgid?(pgid)
      !pgid.is_a?(Integer) || pgid <= 1
    end

    # atomic operation on POSIX filesystems, since
    # f.flock(File::LOCK_SH) is not available on all platforms
    def acquire_atomic_fs_lock(name)
      lock = "#{name}.lock"
      times = 0
      begin
        Dir.mkdir lock, 0o700
      rescue Errno::EEXIST
        times += 1
        if times >= 10
          logger.info("Timeout waiting for lock #{lock}")
          raise "Timeout waiting for lock #{lock}"
        end
        logger.debug("Waiting for lock #{lock}")
        sleep 1
        retry
      end
      logger.debug("Acquired lock #{lock}")
      begin
        yield
      ensure
        clear_atomic_fs_lock(lock)
      end
    end

    def clear_all_atomic_fs_locks
      Dir['.*.lock'].each do |f|
        System.delete_if_exists(f) if File.directory?(f)
      end
    end

    def pid_journal_filename(journal_name)
      File.join(@journal_base_dir, ".bluepill_pids_journal.#{journal_name}")
    end

    def pgid_journal_filename(journal_name)
      File.join(@journal_base_dir, ".bluepill_pgids_journal.#{journal_name}")
    end

    def pid_journal(filename)
      logger.debug("pid journal file: #{filename}")
      result = File.open(filename, 'r').readlines.collect(&:to_i).reject { |pid| skip_pid?(pid) }
      logger.debug("pid journal = #{result.join(' ')}")
      result
    rescue Errno::ENOENT
      []
    end

    def pgid_journal(filename)
      logger.debug("pgid journal file: #{filename}")
      result = File.open(filename, 'r').readlines.collect(&:to_i).reject { |pgid| skip_pgid?(pgid) }
      logger.debug("pgid journal = #{result.join(' ')}")
      result
    rescue Errno::ENOENT
      []
    end

    def clear_atomic_fs_lock(name)
      return unless File.directory?(name)

      Dir.rmdir(name)
      logger.debug("Cleared lock #{name}")
    end

    def kill_all_from_all_journals
      pids = Dir['.bluepill_pids_journal.*'].collect { |p| p.sub(/^\.bluepill_pids_journal\./, '') }
      pids.reject! { |p| p =~ /\.lock$/ }
      pids.each do |journal_name|
        kill_all_from_journal(journal_name)
      end
    end

    def kill_all_from_journal(journal_name)
      kill_all_pids_from_journal(journal_name)
      kill_all_pgids_from_journal(journal_name)
    end

    def kill_all_pgids_from_journal(journal_name)
      filename = pgid_journal_filename(journal_name)
      kill_all_from_journal_file(filename, pgid_journal(filename), 'process group', -1)
    end

    def kill_all_pids_from_journal(journal_name)
      filename = pid_journal_filename(journal_name)
      kill_all_from_journal_file(filename, pid_journal(filename), 'process', 1)
    end

    # Sends TERM, waits a second for any survivors, then sends KILL to those
    # still alive. A negative sign targets process groups instead of pids.
    def kill_all_from_journal_file(filename, ids, label, sign)
      if ids.empty?
        logger.debug('No previous process journal - Skipping cleanup')
        return
      end

      acquire_atomic_fs_lock(filename) do
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

    def signal_journaled(signal, ids, label, sign)
      past, verb = signal == 'TERM' ? %w[Termed term] : %w[Killed kill]
      ids.each do |id|
        begin
          ::Process.kill(signal, sign * id)
          logger.info("#{past} old #{label} #{id}")
        rescue Errno::ESRCH
          logger.debug("Unable to #{verb} missing #{label} #{id}")
        end
      end
    end

    def append_pgid_to_journal(journal_name, pgid)
      if skip_pgid?(pgid)
        logger.debug("Skipping invalid pgid #{pgid} (class #{pgid.class})")
        return
      end

      filename = pgid_journal_filename(journal_name)
      acquire_atomic_fs_lock(filename) do
        if pgid_journal(filename).include?(pgid)
          logger.debug("Skipping duplicate pgid #{pgid} already in journal #{journal_name}")
        else
          logger.debug("Saving pgid #{pgid} to process journal #{journal_name}")
          File.open(filename, 'a+', 0o600) { |f| f.puts(pgid) }
          logger.info("Saved pgid #{pgid} to journal #{journal_name}")
          logger.debug("Journal now = #{File.open(filename, 'r').read}")
        end
      end
    end

    def append_pid_to_journal(journal_name, pid)
      if skip_pid?(pid)
        logger.debug("Skipping invalid pid #{pid} (class #{pid.class})")
        return
      end
      begin
        append_pgid_to_journal(journal_name, ::Process.getpgid(pid))
      rescue Errno::ESRCH
      end

      filename = pid_journal_filename(journal_name)
      acquire_atomic_fs_lock(filename) do
        if pid_journal(filename).include?(pid)
          logger.debug("Skipping duplicate pid #{pid} already in journal #{journal_name}")
        else
          logger.debug("Saving pid #{pid} to process journal #{journal_name}")
          File.open(filename, 'a+', 0o600) { |f| f.puts(pid) }
          logger.info("Saved pid #{pid} to journal #{journal_name}")
          logger.debug("Journal now = #{File.open(filename, 'r').read}")
        end
      end
    end
  end
end
