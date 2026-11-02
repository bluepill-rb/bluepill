# frozen_string_literal: true

require "shellwords"
require "bluepill/daemonize"
require "bluepill/system/command_setup"

module Bluepill
  module System
    # Run commands in the background, as daemons
    #
    # System extends this module, so these are System's module functions.
    #
    # @api private
    module Daemon
      include CommandSetup

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
      def daemonize(cmd, options = {})
        rd, wr = IO.pipe

        child = Daemonize.safefork
        if child
          # we don't want to create zombies, so detach ourselves from the child exit status
          ::Process.detach(child)

          read_daemon_pid(rd, wr)
        else
          # child
          rd.close

          drop_privileges(options[:uid], options[:gid], options[:supplementary_groups])
          start_daemon(cmd, options, wr)
        end
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
      # @param [Hash{Symbol => Object}] options as for daemonize
      # @param [IO] pid_pipe where to write the daemon's pid for the parent
      #
      # @return [void] it never returns, since it exits the child
      #
      # @api private
      def start_daemon(cmd, options, pid_pipe)
        # Processes that bluepill daemonizes always have a pid file and a logger
        pid_file = options[:pid_file] #: String
        logger = options[:logger] #: Logger

        # if we cannot write the pid file as the provided user, err out
        exit unless can_write_pid_file(pid_file, logger)

        daemon_id = Daemonize.call_as_daemon(daemon_command(cmd, options), cmd)

        # call_as_daemon returns 0 when the daemon fails to report its pid
        File.write(pid_file, daemon_id.to_s) if daemon_id > 0

        pid_pipe.write daemon_id
        pid_pipe.close

        ::Process.exit!(true)
      end

      # Return what the daemon runs: the command, in its environment
      #
      # @param [String] cmd the command
      # @param [Hash{Symbol => Object}] options as for daemonize
      #
      # @return [Proc] a block that execs the command
      #
      # @api private
      def daemon_command(cmd, options)
        lambda do
          setup_command_environment(options)
          redirect_io(options[:stdin], options[:stdout], options[:stderr])

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
