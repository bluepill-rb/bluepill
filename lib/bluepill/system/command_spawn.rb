# frozen_string_literal: true

require "shellwords"
require "bluepill/system/command_result"

module Bluepill
  module System
    # Start commands without forking bluepill, in a Ruby that can't fork,
    # such as JRuby
    #
    # The command gets the working directory and environment that a forked
    # one sets up. It can't switch to another user or groups, which a
    # config that sets them fails to load for.
    #
    # Commands and Daemon include it, and System extends them, so these are
    # System's module functions.
    #
    # @api private
    module CommandSpawn
      # The seconds between checks of whether a spawned command has exited
      EXIT_POLL_INTERVAL = 0.05

      # Start a command, without waiting for it to finish
      #
      # @param [String] cmd the command, split into words without a shell
      # @param [CommandOptions] options its working_dir and environment
      # @param [String, nil] chdir the directory to run in without a
      #   working_dir, or nil for bluepill's
      # @param [Hash{Symbol => Object}] redirects more of Process.spawn's
      #   options, such as where its standard streams go
      #
      # @return [Integer] the command's pid
      #
      # @raise [SystemCallError] if it can't be run, say because it doesn't
      #   exist
      #
      # @api private
      def spawn_command(cmd, options, chdir: nil, **redirects)
        dir = options.working_dir&.to_s || chdir
        redirects[:chdir] = dir if dir
        program, *args = Shellwords.shellwords(cmd)
        ::Process.spawn(spawn_environment(options), program.to_s, *args, **redirects)
      end

      # Run a command until it finishes, and return what it printed
      #
      # It's execute_blocking, for a Ruby that can't fork. Two threads read
      # what the command prints, so neither pipe fills up and stops it.
      #
      # @param [String] cmd the command, split into words without a shell
      # @param [CommandOptions] options its working_dir, environment and
      #   timeout
      #
      # @return [CommandResult] what it printed, and its exit code, which is
      #   1 if it couldn't be run
      #
      # @raise [Timeout::Error] if it ran longer than the timeout
      #
      # @api private
      def spawn_blocking(cmd, options)
        out_read, out_write = IO.pipe
        err_read, err_write = IO.pipe
        run_spawned(cmd, options, [out_read, err_read], [out_write, err_write])
      end

      # Spawn a command with its output on pipes, and wait for it to finish
      #
      # @param [String] cmd the command
      # @param [CommandOptions] options as for spawn_blocking
      # @param [Array(IO, IO)] readers the pipes' readers, for its standard
      #   output and standard error, which are closed after
      # @param [Array(IO, IO)] writers the pipes' writers
      #
      # @return [CommandResult] what it printed, and its exit code, which is
      #   1 if it couldn't be run
      #
      # @raise [Timeout::Error] if it ran longer than the timeout
      #
      # @api private
      def run_spawned(cmd, options, readers, writers)
        out, err = writers
        pid = spawn_blocking_command(cmd, options, out, err)
        wait_for_spawned(cmd, options.timeout, pid, readers)
      rescue SystemCallError => e
        CommandResult.new(exit_code: 1, stderr: "Could not run #{cmd}: #{e.message}\n")
      ensure
        readers.each(&:close)
      end

      # Spawn a command that runs until it finishes, with its output on pipes
      #
      # With a timeout, it runs in a process group of its own, which is
      # killed if it runs too long. The pipes' writers are closed here, so
      # they end when the command closes its ends.
      #
      # @param [String] cmd the command
      # @param [CommandOptions] options as for spawn_blocking
      # @param [IO] out the pipe for its standard output
      # @param [IO] err the pipe for its standard error
      #
      # @return [Integer] its pid
      #
      # @raise [SystemCallError] if it can't be run
      #
      # @api private
      def spawn_blocking_command(cmd, options, out, err)
        # pgroup: nil leaves it in bluepill's process group
        spawn_command(cmd, options, in: File::NULL, out:, err:, pgroup: (true if options.timeout))
      ensure
        out.close
        err.close
      end

      # Wait for a spawned command to finish, and collect what it printed
      #
      # @param [String] cmd the command, for the error on a timeout
      # @param [Numeric, ActiveSupport::Duration, nil] timeout the seconds to
      #   wait for it, or nil to wait until it finishes
      # @param [Integer] pid its pid
      # @param [Array(IO, IO)] pipes where to read its standard output and
      #   standard error
      #
      # @return [CommandResult] what it printed, and its exit code (nil if a
      #   signal ended it)
      #
      # @raise [Timeout::Error] if it ran longer than the timeout
      #
      # @api private
      def wait_for_spawned(cmd, timeout, pid, pipes)
        readers = pipes.collect { |pipe| read_in_background(pipe) }
        status = wait_for_exit(pid, timeout) || kill_spawned_after(pid, timeout, cmd)
        stdout, stderr = readers.collect(&:value)
        CommandResult.new(exit_code: status.exitstatus, stdout:, stderr:)
      end

      # Wait for a spawned command to exit, for up to a timeout
      #
      # It polls, since a thread blocked waiting for a process would keep
      # JRuby from exiting until the process does.
      #
      # @param [Integer] pid the command's pid
      # @param [Numeric, ActiveSupport::Duration, nil] timeout the seconds to
      #   wait, or nil to wait until it exits
      #
      # @return [Process::Status, nil] how it exited, or nil if it's still
      #   running at the timeout
      #
      # @api private
      def wait_for_exit(pid, timeout)
        deadline = monotonic_now + timeout.to_f if timeout
        loop do
          _, status = ::Process.wait2(pid, ::Process::WNOHANG)
          return status if status
          return if deadline && monotonic_now >= deadline

          Kernel.sleep(EXIT_POLL_INTERVAL)
        end
      end

      # Kill a spawned command's process group after its timeout, and reap it
      #
      # @param [Integer] pid the command's pid, which leads the group
      # @param [Numeric, ActiveSupport::Duration] timeout the seconds it was given
      # @param [String] cmd the command, for the error
      #
      # @return [void] it never returns
      #
      # @raise [Timeout::Error] always
      #
      # @api private
      def kill_spawned_after(pid, timeout, cmd)
        kill_group_after(pid, timeout, cmd)
      ensure
        begin
          ::Process.wait(pid)
        rescue Errno::ECHILD
          # It was collected already
        end
      end

      # Kill a command's process group, once it has run past its timeout
      #
      # Forked commands are killed this way too.
      #
      # @param [Integer] child the pid of the group's leader, which runs the
      #   command
      # @param [Numeric, ActiveSupport::Duration] timeout the seconds it was given
      # @param [String] cmd the command, for the error
      #
      # @return [void] it never returns
      #
      # @raise [Timeout::Error] always
      #
      # @api private
      def kill_group_after(child, timeout, cmd)
        begin
          ::Process.kill("KILL", -child)
        rescue Errno::ESRCH
          nil # it finished just now
        end
        raise Timeout::Error, "#{cmd} took longer than #{timeout} seconds"
      end

      # Return the seconds on the monotonic clock, as a Float
      #
      # @return [Float]
      #
      # @api private
      def monotonic_now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      # Read a pipe to its end in a thread
      #
      # @param [IO] reader the pipe
      #
      # @return [Thread] a thread whose value is what it read, or "" if the
      #   pipe was closed first, after a timeout
      #
      # @api private
      def read_in_background(reader)
        Thread.new do
          reader.read
        rescue IOError
          ""
        end
      end

      # Return the environment variables a command gets, as Strings
      #
      # PWD is the working directory, as a shell sets it, unless the
      # environment sets it too.
      #
      # @param [CommandOptions] options its working_dir and environment
      #
      # @return [Hash{String => String}]
      #
      # @api private
      def spawn_environment(options)
        working_dir = options.working_dir
        env = options.environment.to_h { |key, value| [key.to_s, value.to_s] }
        working_dir ? {"PWD" => working_dir.to_s}.merge(env) : env
      end
    end
  end
end
