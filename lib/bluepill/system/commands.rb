require 'etc'
require 'shellwords'

module Bluepill
  # Runs commands for bluepill: in the background as daemons, or until they
  # finish, optionally as another user
  module System
  module_function

    # Returns the pid of the child that executes the cmd
    def daemonize(cmd, options = {})
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

          ::Kernel.exec(*Shellwords.shellwords(cmd))
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

    # Returns the stdout, stderr and exit code of the cmd
    def execute_blocking(cmd, options = {})
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

        cmd_status.strip != '' ? Marshal.load(cmd_status) : {exit_code: 0, stdout: '', stderr: ''}
      else
        rd.close
        run_blocking_child(cmd, options, wr)
      end
    end

    # Runs cmd in a grandchild, sends its output and exit code to the parent
    # over result_pipe, and exits
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

    def exec_blocking_grandchild(cmd, options, pipes)
      # @type var cmd_err_write: IO
      cmd_out_read, cmd_out_write = pipes[:out]
      cmd_err_read, cmd_err_write = pipes[:err]

      drop_privileges(options[:uid], options[:gid], options[:supplementary_groups])
      setup_command_environment(options)

      # close unused fds so ancestors wont hang. This line is the only reason we are not
      # using something like popen3. If this fd is not closed, the .read call on the parent
      # will never return because the result pipe would still be open in the "exec"-ed cmd
      pipes[:result].close

      # we do not care about stdin of cmd
      STDIN.reopen('/dev/null')

      # point stdout and stderr of cmd to somewhere we can read
      cmd_out_read.close
      STDOUT.reopen(cmd_out_write)
      cmd_out_write.close
      cmd_err_read.close
      STDERR.reopen(cmd_err_write)
      cmd_err_write.close

      ::Kernel.exec(*Shellwords.shellwords(cmd))
    rescue StandardError => e
      err = cmd_err_write.closed? ? STDERR : cmd_err_write
      err.puts "Exception in grandchild: #{e}."
      err.puts e.backtrace
      exit 1
    end

    def setup_command_environment(options)
      # Setting end PWD env emulates bash behavior when dealing with symlinks
      Dir.chdir(ENV['PWD'] = options[:working_dir].to_s) if options[:working_dir]
      options[:environment].each { |key, value| ENV[key.to_s] = value.to_s } if options[:environment]
    end

    # be sure to call this from a fork otherwise it will modify the attributes
    # of the bluepill daemon
    def drop_privileges(uid, gid, supplementary_groups)
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

    def can_write_pid_file(pid_file, logger)
      FileUtils.touch(pid_file)
      File.unlink(pid_file)
      true
    rescue StandardError => e
      logger.warning(format('%s - %s', e.class.name, e.message))
      Array(e.backtrace).each { |l| logger.warning l }
      false
    end

    def redirect_io(io_in, io_out, io_err)
      $stdin.reopen(io_in) if io_in

      if !io_out.nil? && !io_err.nil? && io_out == io_err
        $stdout.reopen(io_out, APPEND_MODE)
        $stderr.reopen($stdout)

      else
        $stdout.reopen(io_out, APPEND_MODE) if io_out
        $stderr.reopen(io_err, APPEND_MODE) if io_err
      end
    end
  end
end
