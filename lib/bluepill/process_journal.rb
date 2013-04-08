require 'bluepill/system'

module Bluepill
  module ProcessJournal
    extend self

    class << self
      attr_reader :logger
      attr_reader :journal_base_dir

      def logger=(new_logger)
        @logger ||= new_logger
      end

      def base_dir=(base_dir)
        @journal_base_dir ||= File.join(base_dir, "journals")
        FileUtils.mkdir_p(@journal_base_dir) unless File.exists?(@journal_base_dir)
        FileUtils.chmod(0777, @journal_base_dir)
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
      times = 0
      name += '.lock'
      Dir.mkdir name, 0700
      logger.debug("Acquired lock #{name}")
      yield
    rescue Errno::EEXIST
      times += 1
      logger.debug("Waiting for lock #{name}")
      sleep 1
      unless times >= 10
        retry
      else
        logger.info("Timeout waiting for lock #{name}")
        raise "Timeout waiting for lock #{name}"
      end
    ensure
      clear_atomic_fs_lock(name)
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
      result = File.open(filename, 'r').readlines.map(&:to_i).reject {|pid| skip_pid?(pid)}
      logger.debug("pid journal = #{result.join(' ')}")
      result
    rescue Errno::ENOENT
      []
    end

    def pgid_journal(filename)
      logger.debug("pgid journal file: #{filename}")
      result = File.open(filename, 'r').readlines.map(&:to_i).reject {|pgid| skip_pgid?(pgid)}
      logger.debug("pgid journal = #{result.join(' ')}")
      result
    rescue Errno::ENOENT
      []
    end

    def clear_atomic_fs_lock(name)
      if File.directory?(name)
        Dir.rmdir(name)
        logger.debug("Cleared lock #{name}")
      end
    end

    def kill_all_from_all_journals
      Dir[".bluepill_pids_journal.*"].map { |x|
        x.sub(/^\.bluepill_pids_journal\./,"")
      }.reject { |y|
        y =~ /\.lock$/
      }.each do |journal_name|
        kill_all_from_journal(journal_name)
      end
    end

    def kill_all_from_journal(journal_name)
      kill_all_pids_from_journal(journal_name)
      kill_all_pgids_from_journal(journal_name)
    end

    def kill_all_pgids_from_journal(journal_name)
      filename = pgid_journal_filename(journal_name)
      j = pgid_journal(filename)
      if j.length > 0
        acquire_atomic_fs_lock(filename) do
          j.each do |pgid|
            begin
              ::Process.kill('TERM', -pgid)
              logger.info("Termed old process group #{pgid}")
            rescue Errno::ESRCH
              logger.debug("Unable to term missing process group #{pgid}")
            end
          end

          if j.select { |pgid| System.pid_alive?(pgid) }.length > 1
            sleep(1)
            j.each do |pgid|
              begin
                ::Process.kill('KILL', -pgid)
                logger.info("Killed old process group #{pgid}")
              rescue Errno::ESRCH
                logger.debug("Unable to kill missing process group #{pgid}")
              end
            end
          end
          System.delete_if_exists(filename) # reset journal
          logger.debug('Journal cleanup completed')
        end
      else
        logger.debug('No previous process journal - Skipping cleanup')
      end
    end

    def kill_all_pids_from_journal(journal_name)
      filename = pid_journal_filename(journal_name)
      j = pid_journal(filename)
      if j.length > 0
        acquire_atomic_fs_lock(filename) do
          j.each do |pid|
            begin
              ::Process.kill('TERM', pid)
              logger.info("Termed old process #{pid}")
            rescue Errno::ESRCH
              logger.debug("Unable to term missing process #{pid}")
            end
          end

          if j.select { |pid| System.pid_alive?(pid) }.length > 1
            sleep(1)
            j.each do |pid|
              begin
                ::Process.kill('KILL', pid)
                logger.info("Killed old process #{pid}")
              rescue Errno::ESRCH
                logger.debug("Unable to kill missing process #{pid}")
              end
            end
          end
          System.delete_if_exists(filename) # reset journal
          logger.debug('Journal cleanup completed')
        end
      else
        logger.debug('No previous process journal - Skipping cleanup')
      end
    end

    def append_pgid_to_journal(journal_name, pgid)
      if skip_pgid?(pgid)
        logger.debug("Skipping invalid pgid #{pgid} (class #{pgid.class})")
        return
      end

      filename = pgid_journal_filename(journal_name)
      acquire_atomic_fs_lock(filename) do
        unless pgid_journal(filename).include?(pgid)
          logger.debug("Saving pgid #{pgid} to process journal #{journal_name}")
          File.open(filename, 'a+', 0600) { |f| f.puts(pgid) }
          logger.info("Saved pgid #{pgid} to journal #{journal_name}")
          logger.debug("Journal now = #{File.open(filename, 'r').read}")
        else
          logger.debug("Skipping duplicate pgid #{pgid} already in journal #{journal_name}")
        end
      end
    end

    def append_pid_to_journal(journal_name, pid)
      begin
        append_pgid_to_journal(journal_name, ::Process.getpgid(pid))
      rescue Errno::ESRCH
      end
      if skip_pid?(pid)
        logger.debug("Skipping invalid pid #{pid} (class #{pid.class})")
        return
      end

      filename = pid_journal_filename(journal_name)
      acquire_atomic_fs_lock(filename) do
        unless pid_journal(filename).include?(pid)
          logger.debug("Saving pid #{pid} to process journal #{journal_name}")
          File.open(filename, 'a+', 0600) { |f| f.puts(pid) }
          logger.info("Saved pid #{pid} to journal #{journal_name}")
          logger.debug("Journal now = #{File.open(filename, 'r').read}")
        else
          logger.debug("Skipping duplicate pid #{pid} already in journal #{journal_name}")
        end
      end
    end
  end
end
