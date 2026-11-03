# frozen_string_literal: true

require "shellwords"
require "bluepill/daemonize"
require "bluepill/system/command_options"
require "bluepill/system/command_setup"
require "bluepill/system/command_spawn"

module Bluepill
  module System
    # The mode that a daemon's stdout and stderr files are opened in
    #
    # @api private
    APPEND_MODE = "a"

    # Run commands in the background, as daemons
    #
    # System extends this module, so these are System's module functions.
    #
    # @api private
    module Daemon
      include CommandSetup
      include CommandSpawn

      # Start a command as a daemon, and write its pid file
      #
      # It forks a child that drops privileges, sets up the environment and
      # standard streams, and daemonizes the command. The child tells the
      # parent the daemon's pid over a pipe. A Ruby that can't fork spawns
      # the command instead.
      #
      # @param [String] cmd the command, split into words without a shell
      # @param [CommandOptions] options its uid, gid, supplementary_groups,
      #   working_dir, environment, stdin, stdout and stderr
      # @param [String] pid_file where to write the daemon's pid
      # @param [Logger] logger where to log why the pid file can't be written
      #
      # @return [Integer, nil] the daemon's pid, or nil if it didn't start
      #
      # @api private
      def daemonize(cmd, options = CommandOptions.new, pid_file:, logger:)
        return fork_daemon(cmd, options, pid_file:, logger:) if Daemonize.can_fork?

        spawn_daemon(cmd, options, pid_file:, logger:)
      end

      # Start a command as a daemon by forking, and write its pid file
      #
      # @param (see #daemonize)
      #
      # @return [Integer, nil] the daemon's pid, or nil if it didn't start
      #
      # @api private
      def fork_daemon(cmd, options, pid_file:, logger:)
        rd, wr = IO.pipe

        child = Daemonize.safefork
        if child
          # we don't want to create zombies, so detach ourselves from the child exit status
          ::Process.detach(child)

          read_daemon_pid(rd, wr)
        else
          # child
          rd.close

          drop_privileges(options.uid, options.gid, options.supplementary_groups)
          start_daemon(cmd, options, wr, pid_file:, logger:)
        end
      end

      # Start a command as a daemon without forking, and write its pid file
      #
      # The command runs in a process group of its own, as a forked daemon's
      # new session does, so killing what's left in it never kills bluepill.
      # It stays bluepill's child, and pid_alive? collects its exit status.
      # One that runs as another user opens its files as that user, and its
      # pid file is the user's, as a forked daemon's are.
      #
      # @param [String] cmd the command, split into words without a shell
      # @param [CommandOptions] options its working_dir, environment, stdin,
      #   stdout, stderr, uid, gid and supplementary_groups
      # @param [String] pid_file where to write the daemon's pid
      # @param [Logger] logger where to log why it didn't start
      #
      # @return [Integer, nil] the daemon's pid, or nil if it didn't start
      #
      # @api private
      def spawn_daemon(cmd, options, pid_file:, logger:)
        return unless spawned_can_write_pid_file(pid_file, options, logger)

        pid = spawn_command(cmd, options, chdir: "/", pgroup: true, **spawned_daemon_streams(options))
        File.write(pid_file, pid.to_s)
        chown_to_switched(pid_file, options)
        pid
      rescue SystemCallError => e
        logger.warning(format("%s - %s", e.class, e))
        nil
      end

      # Return whether a spawned daemon's pid file can be written
      #
      # It's checked as the user the daemon runs as, as a forked daemon
      # checks it once it has switched.
      #
      # @param [String] pid_file the pid file's path
      # @param [CommandOptions] options its uid, gid and supplementary_groups
      # @param [Logger] logger where to log why it can't be written
      #
      # @return [Boolean]
      #
      # @api private
      def spawned_can_write_pid_file(pid_file, options, logger)
        return can_write_pid_file(pid_file, logger) unless switches_user?(options)
        return true if switched_can_write?(pid_file, options)

        logger.warning("Can't write the pid file #{pid_file} as the process's user and groups")
        false
      end

      # Return Kernel.spawn's options for a spawned daemon's standard streams
      #
      # A daemon that runs as another user opens its files itself, as the
      # user, so Kernel.spawn points the streams at /dev/null until then.
      #
      # @param [CommandOptions] options its stdin, stdout and stderr
      #
      # @return [Hash{Symbol => Object}] in, out and err, and the files for
      #   spawn_command to open as the user
      #
      # @api private
      def spawned_daemon_streams(options)
        return daemon_streams(options) unless switches_user?(options)

        {in: File::NULL, out: File::NULL, err: File::NULL, files: [options.stdin, options.stdout, options.stderr]}
      end

      # Return where a spawned daemon's standard streams go
      #
      # They're /dev/null unless the options name files. Output and error
      # share one file when they name the same one, and are appended to.
      #
      # @param [CommandOptions] options its stdin, stdout and stderr
      #
      # @return [Hash{Symbol => Object}] Kernel.spawn's in, out and err
      #
      # @api private
      def daemon_streams(options)
        out = options.stdout
        {
          in: options.stdin || File::NULL,
          out: out ? [out, APPEND_MODE] : File::NULL,
          err: daemon_stderr(out, options.stderr)
        }
      end

      # Return where a spawned daemon's standard error goes
      #
      # @param [String, nil] out the file for standard output
      # @param [String, nil] err the file for standard error
      #
      # @return [Object] Kernel.spawn's err: standard output when they're
      #   the same file, the file, or /dev/null
      #
      # @api private
      def daemon_stderr(out, err)
        return File::NULL unless err
        return [:child, :out] if err.eql?(out)

        [err, APPEND_MODE]
      end

      # Read the daemon's pid from the child that started it, in the parent
      #
      # @param [IO] reader the end of the pipe that the child writes the pid to
      # @param [IO] writer the other end, which only the child uses
      #
      # @return [Integer, nil] the daemon's pid, or nil if it didn't start
      #
      # @api private
      def read_daemon_pid(reader, writer)
        # parent
        writer.close

        daemon_id = reader.read.to_i
        reader.close

        daemon_id if daemon_id > 0
      end

      # Daemonize the command, write its pid file, and tell the parent its pid
      #
      # It runs in the child, once it has dropped privileges.
      #
      # @param [String] cmd the command
      # @param [CommandOptions] options as for daemonize
      # @param [IO] pid_pipe where to write the daemon's pid for the parent
      # @param [String] pid_file where to write the daemon's pid
      # @param [Logger] logger where to log why the pid file can't be written
      #
      # @return [void] it never returns, since it exits the child
      #
      # @api private
      def start_daemon(cmd, options, pid_pipe, pid_file:, logger:)
        # if we cannot write the pid file as the provided user, err out
        exit unless can_write_pid_file(pid_file, logger)

        daemon_id = Daemonize.call_as_daemon(daemon_command(cmd, options), cmd)

        # call_as_daemon returns 0 when the daemon fails to report its pid
        File.write(pid_file, daemon_id.to_s) if daemon_id > 0

        pid_pipe.write daemon_id
        pid_pipe.close

        Kernel.exit!(true)
      end

      # Return what the daemon runs: the command, in its environment
      #
      # @param [String] cmd the command
      # @param [CommandOptions] options as for daemonize
      #
      # @return [Proc] a block that execs the command
      #
      # @api private
      def daemon_command(cmd, options)
        lambda do
          setup_command_environment(options)
          redirect_io(options.stdin, options.stdout, options.stderr)

          Kernel.exec(*Shellwords.shellwords(cmd))
          exit
        end
      end

      # Return whether the pid file can be written, logging why if it can't
      #
      # @param [String] pid_file the pid file's path
      # @param [Logger] logger where to log the error
      #
      # @return [Boolean] true if the file could be created and removed
      #
      # @api private
      def can_write_pid_file(pid_file, logger)
        FileUtils.touch(pid_file)
        File.unlink(pid_file)
        true
      rescue => e
        logger.warning(format("%s - %s", e.class, e))
        # A rescued exception was raised, so it has a backtrace
        backtrace = e.backtrace #: Array[String]
        backtrace.each { |l| logger.warning l }
        false
      end

      # Point standard input, output and error at files
      #
      # Output and error share one file when they name the same one. It
      # reopens STDIN, STDOUT and STDERR, which are always file descriptors
      # 0, 1 and 2, the ones the command inherits, even if $stdout and the
      # others have been pointed somewhere else.
      #
      # @param [String, nil] io_in the file for standard input
      # @param [String, nil] io_out the file for standard output, appended to
      # @param [String, nil] io_err the file for standard error, appended to
      #
      # @return [void]
      #
      # @api private
      def redirect_io(io_in, io_out, io_err)
        STDIN.reopen(io_in) if io_in

        if !io_out.nil? && io_out.eql?(io_err)
          STDOUT.reopen(io_out, APPEND_MODE)
          STDERR.reopen(STDOUT)

        else
          STDOUT.reopen(io_out, APPEND_MODE) if io_out
          STDERR.reopen(io_err, APPEND_MODE) if io_err
        end
      end
    end
  end
end
