# frozen_string_literal: true

require "io/wait"
require "shellwords"
require "bluepill/daemonize"
require "bluepill/system/command_options"
require "bluepill/system/command_result"
require "bluepill/system/command_setup"
require "bluepill/system/command_spawn"
require "bluepill/system/daemon"

module Bluepill
  module System
    # Run commands until they finish, and collect what they print
    #
    # System extends this module, so these are System's module functions.
    # Daemon runs commands in the background instead.
    #
    # @api private
    module Commands
      include CommandSetup
      include CommandSpawn

      # Run a command until it finishes, and return what it printed
      #
      # With a timeout, the command runs in a process group of its own, and
      # if it hasn't finished in time, that whole group is killed, so a hung
      # command and anything it started don't keep running. A Ruby that
      # can't fork spawns the command instead.
      #
      # @param [String] cmd the command, split into words without a shell
      # @param [CommandOptions] options its uid, gid, supplementary_groups,
      #   working_dir, environment and timeout
      #
      # @return [CommandResult] what it printed, and its exit code
      #
      # @raise [Timeout::Error] if it ran longer than the timeout
      #
      # @api private
      def execute_blocking(cmd, options = CommandOptions.new)
        return spawn_blocking(cmd, options) unless Daemonize.can_fork?

        rd, wr = IO.pipe

        child = Daemonize.safefork
        return start_blocking_child(cmd, options, rd, wr) unless child

        # Reap the child in a background thread, so it never becomes a zombie,
        # even if a timeout interrupts us before it exits
        waiter = ::Process.detach(child)

        wr.close
        cmd_status = read_blocking_status(cmd, options.timeout, child, rd)
        waiter.join

        return CommandResult.new(exit_code: 0) if cmd_status.empty?

        # The child sends a Hash, so loading it needs only core classes
        CommandResult.from_h(Marshal.load(cmd_status))
      end

      # Run the command in the child, which execute_blocking forked
      #
      # With a timeout, the child gets a process group of its own first.
      #
      # @param [String] cmd the command
      # @param [CommandOptions] options as for execute_blocking
      # @param [IO] reader the end of the pipe that only the parent uses
      # @param [IO] result_pipe where to write the result, marshaled
      #
      # @return [void] it never returns, since it exits the child
      #
      # @api private
      def start_blocking_child(cmd, options, reader, result_pipe)
        reader.close
        # The command and what it starts can all be killed at once on a timeout
        ::Process.setpgid(0, 0) if options.timeout
        run_blocking_child(cmd, options, result_pipe)
      end

      # Read what the child reports about the command, in the parent
      #
      # @param [String] cmd the command, for the error on a timeout
      # @param [Numeric, ActiveSupport::Duration, nil] timeout the seconds to
      #   wait for it, or nil to wait until it finishes
      # @param [Integer] child the child's pid
      # @param [IO] reader the end of the pipe that the child writes to
      #
      # @return [String] the marshaled result, or "" if the child reported
      #   nothing
      #
      # @raise [Timeout::Error] if it ran longer than the timeout
      #
      # @api private
      def read_blocking_status(cmd, timeout, child, reader)
        ready = timeout.nil? || reader.wait_readable(timeout.to_f)
        kill_group_after(child, timeout, cmd) unless ready
        reader.read
      ensure
        reader.close
      end

      # Run a command in a grandchild, report its result, and exit
      #
      # Sends the grandchild's output and exit code to the parent over
      # result_pipe.
      #
      # @param [String] cmd the command
      # @param [CommandOptions] options as for execute_blocking
      # @param [IO] result_pipe where to write the result, marshaled
      #
      # @return [void] it never returns, since it exits the child
      #
      # @api private
      def run_blocking_child(cmd, options, result_pipe)
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

        report_blocking_result(result_pipe, collect_blocking_result(pid, cmd_out_read, cmd_err_read))
      end

      # Wait for the grandchild to finish, and collect what it printed
      #
      # @param [Integer] pid the grandchild's pid
      # @param [IO] cmd_out_read where to read its standard output
      # @param [IO] cmd_err_read where to read its standard error
      #
      # @return [Hash{Symbol => Object}] its :stdout and :stderr Strings, and
      #   its :exit_code (nil if a signal ended it)
      #
      # @api private
      def collect_blocking_result(pid, cmd_out_read, cmd_err_read)
        # wait for the cmd to finish executing and acknowledge it's death
        _, status = ::Process.waitpid2(pid)

        # @type var result: blocking_result
        result = {
          stdout: cmd_out_read.read,
          stderr: cmd_err_read.read,
          exit_code: status.exitstatus
        }
        cmd_out_read.close
        cmd_err_read.close
        result
      end

      # Tell the parent the command's result, and exit the child
      #
      # @param [IO] result_pipe where to write the result, marshaled
      # @param [Hash{Symbol => Object}] result the command's result
      #
      # @return [void] it never returns, since it exits the child
      #
      # @api private
      def report_blocking_result(result_pipe, result)
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
      # @param [CommandOptions] options as for execute_blocking
      # @param [Hash{Symbol => Object}] pipes the :out and :err pipes, each a
      #   reader and a writer, and the :result pipe
      #
      # @return [void] it never returns, since it execs the command, or exits
      #   with status 1 if it can't
      #
      # @api private
      def exec_blocking_grandchild(cmd, options, pipes)
        drop_privileges(options.uid, options.gid, options.supplementary_groups)
        setup_command_environment(options)

        # close unused fds so ancestors wont hang. This line is the only reason we are not
        # using something like popen3. If this fd is not closed, the .read call on the parent
        # will never return because the result pipe would still be open in the "exec"-ed cmd
        pipes.fetch(:result).close

        # we do not care about stdin of cmd
        STDIN.reopen(File::NULL)

        # point stdout and stderr of cmd to somewhere we can read
        reopen_on_pipe(STDOUT, pipes.fetch(:out))
        reopen_on_pipe(STDERR, pipes.fetch(:err))

        Kernel.exec(*Shellwords.shellwords(cmd))
      rescue => e
        report_grandchild_error(e, pipes)
      end

      # Point a standard stream at a pipe's writer, and close the pipe's ends
      #
      # @param [IO] stream STDOUT or STDERR
      # @param [Array(IO, IO)] pipe the pipe's reader, which only the
      #   grandchild's parent uses, and its writer
      #
      # @return [void]
      #
      # @api private
      def reopen_on_pipe(stream, pipe)
        reader, writer = pipe
        reader.close
        stream.reopen(writer)
        writer.close
      end

      # Print why the grandchild couldn't exec the command, and exit
      #
      # It prints to the pipe for the command's standard error, unless that's
      # closed already.
      #
      # @param [Exception] error what went wrong
      # @param [Hash{Symbol => Object}] pipes as for exec_blocking_grandchild
      #
      # @return [void] it never returns, since it exits with status 1
      #
      # @api private
      def report_grandchild_error(error, pipes)
        cmd_err_write = pipes.fetch(:err).last
        err = cmd_err_write.closed? ? STDERR : cmd_err_write
        err.puts "Exception in grandchild: #{error}."
        err.puts error.backtrace
        exit 1
      end
    end
  end
end
