# frozen_string_literal: true

module Bluepill
  module ProcessJournal
    # Lock a journal while bluepill reads and writes it
    #
    # Processes that run as other users write to the same journals, so each
    # journal has a lock: a directory next to it, since making one is atomic
    # on POSIX filesystems and f.flock(File::LOCK_SH) is not available on all
    # platforms. ProcessJournal extends it.
    #
    # @api private
    module Lock
      # Run a block while holding a lock on a journal
      #
      # It waits up to 10 seconds for another process's lock.
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
      def acquire_atomic_fs_lock(name)
        lock = "#{name}.lock"
        make_atomic_fs_lock(lock)
        logger.debug("Acquired lock #{lock}")
        begin
          yield
        ensure
          clear_atomic_fs_lock(lock)
        end
      end

      # Remove the app's journal locks, which a daemon that died left behind
      #
      # Without this, a stale lock would make the next write to its journal
      # wait 10 seconds and fail.
      #
      # @return [void]
      #
      # @api private
      def clear_all_atomic_fs_locks
        Dir[File.join(journal_base_dir, ".*.lock")].each do |lock|
          clear_atomic_fs_lock(lock)
        end
      end

      # Release a journal lock, if it's there
      #
      # @param [String] name the lock's directory
      #
      # @return [void]
      #
      # @api private
      def clear_atomic_fs_lock(name)
        return unless File.directory?(name)

        Dir.rmdir(name)
        logger.debug("Cleared lock #{name}")
      end

      # Make a lock's directory, waiting for another process to release it
      #
      # @param [String] lock the lock's directory
      #
      # @return [void]
      #
      # @raise [RuntimeError] if the lock is still held after 10 tries
      #
      # @api private
      def make_atomic_fs_lock(lock)
        attempts = 0
        begin
          Dir.mkdir lock, 0o700
        rescue Errno::EEXIST
          attempts += 1
          wait_for_atomic_fs_lock(lock, attempts)
          retry
        end
      end

      # Wait a second for another process's lock, unless that's been 10 tries
      #
      # @param [String] lock the lock's directory
      # @param [Integer] attempts how many times making it has failed
      #
      # @return [void]
      #
      # @raise [RuntimeError] after the 10th try
      #
      # @api private
      def wait_for_atomic_fs_lock(lock, attempts)
        if attempts < 10
          logger.debug("Waiting for lock #{lock}")
          sleep 1
        else
          logger.info("Timeout waiting for lock #{lock}")
          raise "Timeout waiting for lock #{lock}"
        end
      end
    end
  end
end
