require 'etc'
require 'shellwords'

module Bluepill
  module System
    # Runs commands for bluepill: in the background as daemons, or until they
    # finish, optionally as another user. System's documentation is in
    # system.rb.

    # Start a command as a daemon, and write its pid file
    #
    # It forks a child that drops privileges, sets up the environment and
    # standard streams, and daemonizes the command. The child tells the
    # parent the daemon's pid over a pipe.
    #
    # @param [String] cmd the command, split into words without a shell
    # @param [Hash{Symbol => Object}] options :uid, :gid,
    #   :supplementary_groups, :working_dir, :environment, :pid_file,
    #   :logger, :stdin, :stdout and :stderr
    #
    # @return [Integer, nil] the daemon's pid, or nil if it didn't start
    #
    # @api private
    def self.daemonize(cmd, options = {})
      rd, wr = IO.pipe

      child = Daemonize.safefork
      if child
        # we don't want to create zombies, so detach ourselves from the child exit status
        ::Process.detach(child)

        # parent
        wr.close

        daemon_id = rd.read.to_i
        rd.close

        daemon_id if daemon_id > 0
      else
        # child
        rd.close

        drop_privileges(options[:uid], options[:gid], options[:supplementary_groups])

        # Processes that bluepill daemonizes always have a pid file and a logger
        pid_file = options[:pid_file] #: String
        logger = options[:logger] #: Logger

        # if we cannot write the pid file as the provided user, err out
        exit unless can_write_pid_file(pid_file, logger)

        to_daemonize = lambda do
          setup_command_environment(options)
          redirect_io(options[:stdin], options[:stdout], options[:stderr])

          Kernel.exec(*Shellwords.shellwords(cmd))
          exit
        end

        daemon_id = Daemonize.call_as_daemon(to_daemonize, nil, cmd)

        # call_as_daemon returns 0 when the daemon fails to report its pid
        File.open(pid_file, 'w') { |f| f.write(daemon_id) } if daemon_id > 0

        wr.write daemon_id
        wr.close

        ::Process.exit!(true)
      end
    end

    # Run a command until it finishes, and return what it printed
    #
    # @param [String] cmd the command, split into words without a shell
    # @param [Hash{Symbol => Object}] options :uid, :gid,
    #   :supplementary_groups, :working_dir and :environment
    #
    # @return [Hash{Symbol => Object}] its :stdout and :stderr Strings, and
    #   its :exit_code (nil if a signal ended it)
    #
    # @api private
    def self.execute_blocking(cmd, options = {})
      rd, wr = IO.pipe

      child = Daemonize.safefork
      if child
        # Reap the child in a background thread, so it never becomes a zombie,
        # even if a timeout interrupts us before it exits
        waiter = ::Process.detach(child)

        wr.close
        # @type var cmd_status: String
        begin
          cmd_status = rd.read
        ensure
          rd.close
        end
        waiter.join

        cmd_status.empty? ? {exit_code: 0, stdout: '', stderr: ''} : Marshal.load(cmd_status)
      else
        rd.close
        run_blocking_child(cmd, options, wr)
      end
    end

    # Run a command in a grandchild, report its result, and exit
    #
    # Sends the grandchild's output and exit code to the parent over
    # result_pipe.
    #
    # @param [String] cmd the command
    # @param [Hash{Symbol => Object}] options as for execute_blocking
    # @param [IO] result_pipe where to write the result, marshaled
    #
    # @return [void] it never returns, since it exits the child
    #
    # @api private
    def self.run_blocking_child(cmd, options, result_pipe)
      # create a child in which we can override the stdin, stdout and stderr
      cmd_out_read, cmd_out_write = IO.pipe
      cmd_err_read, cmd_err_write = IO.pipe

      pid = fork do
        # @type var pipes: grandchild_pipes
        pipes = {out: [cmd_out_read, cmd_out_write], err: [cmd_err_read, cmd_err_write], result: result_pipe}
        exec_blocking_grandchild(cmd, options, pipes)
      end

      # we do not use these ends of the pipes in the child
      cmd_out_write.close
      cmd_err_write.close

      # wait for the cmd to finish executing and acknowledge it's death
      _, status = ::Process.waitpid2(pid)

      result = {
        stdout: cmd_out_read.read,
        stderr: cmd_err_read.read,
        exit_code: status.exitstatus,
      }
      cmd_out_read.close
      cmd_err_read.close

      # Time to tell the parent about what went down
      begin
        result_pipe.write Marshal.dump(result)
      rescue Errno::EPIPE
        # The parent timed out and stopped waiting for the result
      end
      result_pipe.close

      ::Process.exit!
    end

    # Replace the grandchild with the command, its output going to the pipes
    #
    # @param [String] cmd the command
    # @param [Hash{Symbol => Object}] options as for execute_blocking
    # @param [Hash{Symbol => Object}] pipes the :out and :err pipes, each a
    #   reader and a writer, and the :result pipe
    #
    # @return [void] it never returns, since it execs the command, or exits
    #   with status 1 if it can't
    #
    # @api private
    def self.exec_blocking_grandchild(cmd, options, pipes)
      # @type var cmd_err_write: IO
      cmd_out_read, cmd_out_write = pipes.fetch(:out)
      cmd_err_read, cmd_err_write = pipes.fetch(:err)

      drop_privileges(options[:uid], options[:gid], options[:supplementary_groups])
      setup_command_environment(options)

      # close unused fds so ancestors wont hang. This line is the only reason we are not
      # using something like popen3. If this fd is not closed, the .read call on the parent
      # will never return because the result pipe would still be open in the "exec"-ed cmd
      pipes.fetch(:result).close

      # we do not care about stdin of cmd
      STDIN.reopen('/dev/null')

      # point stdout and stderr of cmd to somewhere we can read
      cmd_out_read.close
      STDOUT.reopen(cmd_out_write)
      cmd_out_write.close
      cmd_err_read.close
      STDERR.reopen(cmd_err_write)
      cmd_err_write.close

      Kernel.exec(*Shellwords.shellwords(cmd))
    rescue StandardError => e
      err = cmd_err_write.closed? ? STDERR : cmd_err_write
      err.puts "Exception in grandchild: #{e}."
      err.puts e.backtrace
      exit 1
    end

    # Change to the command's working directory and set its environment
    #
    # @param [Hash{Symbol => Object}] options :working_dir and :environment
    #
    # @return [void]
    #
    # @api private
    def self.setup_command_environment(options)
      # Setting end PWD env emulates bash behavior when dealing with symlinks
      working_dir = options[:working_dir]
      Dir.chdir(ENV['PWD'] = working_dir.to_s) if working_dir
      environment = options[:environment]
      environment.each { |key, value| ENV[key.to_s] = value.to_s } if environment
    end

    # Switch to another user and groups, when bluepill runs as root
    #
    # Be sure to call this from a fork, or it changes the user and groups of
    # the bluepill daemon itself.
    #
    # @param [String, nil] uid the user's name
    # @param [String, nil] gid the group's name
    # @param [Array<String>, nil] supplementary_groups more groups' names
    #
    # @return [void]
    #
    # @api private
    def self.drop_privileges(uid, gid, supplementary_groups)
      return unless ::Process::Sys.geteuid.zero?

      uid_num = Etc.getpwnam(uid).uid if uid
      gid_num = Etc.getgrnam(gid).gid if gid
      supplementary_groups ||= [] #: Array[String]
      group_nums = supplementary_groups.collect do |group|
        Etc.getgrnam(group).gid
      end
      ::Process.groups = [gid_num] if gid_num
      ::Process.groups |= group_nums unless group_nums.empty?
      ::Process::Sys.setgid(gid_num) if gid_num
      ::Process::Sys.setuid(uid_num) if uid_num
      ENV['HOME'] = Etc.getpwuid(uid_num).try(:dir) || ENV['HOME'] if uid_num
    end

    # Return whether the pid file can be written, logging why if it can't
    #
    # @param [String] pid_file the pid file's path
    # @param [Logger] logger where to log the error
    #
    # @return [Boolean] true if the file could be created and removed
    #
    # @api private
    def self.can_write_pid_file(pid_file, logger)
      FileUtils.touch(pid_file)
      File.unlink(pid_file)
      true
    rescue StandardError => e
      logger.warning(format('%s - %s', e.class, e))
      # A rescued exception was raised, so it has a backtrace
      backtrace = e.backtrace #: Array[String]
      backtrace.each { |l| logger.warning l }
      false
    end

    # Point standard input, output and error at files
    #
    # Output and error share one file when they name the same one.
    #
    # @param [String, nil] io_in the file for standard input
    # @param [String, nil] io_out the file for standard output, appended to
    # @param [String, nil] io_err the file for standard error, appended to
    #
    # @return [void]
    #
    # @api private
    def self.redirect_io(io_in, io_out, io_err)
      $stdin.reopen(io_in) if io_in

      if !io_out.nil? && io_out.eql?(io_err)
        $stdout.reopen(io_out, APPEND_MODE)
        $stderr.reopen($stdout)

      else
        $stdout.reopen(io_out, APPEND_MODE) if io_out
        $stderr.reopen(io_err, APPEND_MODE) if io_err
      end
    end
  end
end
