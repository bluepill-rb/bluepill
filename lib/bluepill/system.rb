require 'etc'

module Bluepill
  # This class represents the system that bluepill is running on.. It's mainly used to memoize
  # results of running ps auxx etc so that every watch in the every process will not result in a fork
  module System
    extend self
    
    # The position of each field in ps output
    IDX_MAP = {
      :pid => 0,
      :ppid => 1,
      :pcpu => 2,
      :rss => 3
    }
    
    def pid_alive?(pid)
      begin
        ::Process.kill(0, pid)
        true
      rescue Errno::ESRCH
        false
      end
    end
    
    def cpu_usage(pid)
      ps_axu[pid] && ps_axu[pid][IDX_MAP[:pcpu]].to_f
    end
    
    def memory_usage(pid)
      ps_axu[pid] && ps_axu[pid][IDX_MAP[:rss]].to_f
    end
    
    def get_children(parent_pid)
      returning(Array.new) do |child_pids|
        ps_axu.each_pair do |pid, chunks| 
          child_pids << chunks[IDX_MAP[:pid]].to_i if chunks[IDX_MAP[:ppid]].to_i == parent_pid.to_i
        end
      end
    end
    
    # Returns the pid of the child that executes the cmd
    def daemonize(cmd, options = {})
      rd, wr = IO.pipe

      if child = Daemonize.safefork
        # we do not wanna create zombies, so detach ourselves from the child exit status
        ::Process.detach(child)
        
        # parent
        wr.close
        
        daemon_id = rd.read.to_i
        rd.close
          
        return daemon_id if daemon_id > 0
        
      else
        # child
        rd.close

        drop_privileges(options[:uid], options[:gid])
        
        # if we cannot write the pid file as the provided user, err out
        exit unless can_write_pid_file(options[:pid_file], options[:logger])
        
        to_daemonize = lambda do
          # Setting end PWD env emulates bash behavior when dealing with symlinks
          Dir.chdir(ENV["PWD"] = options[:working_dir]) if options[:working_dir]
          
          # Forcing execution through bash to make output redirection and shell exapansion in commands work and still have
          # bluepill monitor the correct process
          args = ["/bin/sh", "-c", "--", cmd]
          
          ::Kernel.exec(*args)
          exit
        end

        daemon_id = Daemonize.call_as_daemon(to_daemonize, nil, cmd)
        
        # Kludge. In order to make bluepill monitor the correct process while given start_commands of the form
        # "cd /some/dir && ./some/server > /tmp/server.log 2>&1"
        # we inspect the children of the "sh -c" process and pick it's single child. 
        # There are many cases where this could break. If Bluepill is not monitoring the correct process, try
        # simplyfying the start_command by moving all the bash scripting to a separate file and specifying that
        # as the start_command. That said, this should work for 99% use cases.
        spawned_children = get_children(daemon_id)
        daemon_id = spawned_children.first if spawned_children.length == 1
        
        File.open(options[:pid_file], "w") {|f| f.write(daemon_id)}
        
        wr.write daemon_id        
        wr.close

        exit
      end
    end
    
    # Returns the stdout, stderr and exit code of the cmd
    def execute_blocking(cmd, options = {})
      rd, wr = IO.pipe
      
      if child = Daemonize.safefork
        # parent
        wr.close
        
        cmd_status = rd.read
        rd.close
        
        ::Process.waitpid(child)
        
        return Marshal.load(cmd_status)
        
      else
        # child
        rd.close
        
        # create a child in which we can override the stdin, stdout and stderr
        cmd_out_read, cmd_out_write = IO.pipe
        cmd_err_read, cmd_err_write = IO.pipe
        
        pid = fork {
          # grandchild
          drop_privileges(options[:uid], options[:gid])
          
          Dir.chdir(ENV["PWD"] = options[:working_dir]) if options[:working_dir]
          
          # close unused fds so ancestors wont hang. This line is the only reason we are not
          # using something like popen3. If this fd is not closed, the .read call on the parent
          # will never return because "wr" would still be open in the "exec"-ed cmd
          wr.close

          # we do not care about stdin of cmd
          STDIN.reopen("/dev/null")

          # point stdout of cmd to somewhere we can read
          cmd_out_read.close
          STDOUT.reopen(cmd_out_write)
          cmd_out_write.close

          # same thing for stderr
          cmd_err_read.close
          STDERR.reopen(cmd_err_write)
          cmd_err_write.close

          # finally, replace grandchild with cmd
          ::Kernel.exec(cmd)
        }

        # we do not use these ends of the pipes in the child
        cmd_out_write.close
        cmd_err_write.close
        
        # wait for the cmd to finish executing and acknowledge it's death
        ::Process.waitpid(pid)
        
        # collect stdout, stderr and exitcode
        result = {
          :stdout => cmd_out_read.read,
          :stderr => cmd_err_read.read,
          :exit_code => $?.exitstatus
        }

        # We're done with these ends of the pipes as well
        cmd_out_read.close
        cmd_err_read.close
        
        # Time to tell the parent about what went down
        wr.write Marshal.dump(result)
        wr.close

        exit  
      end
    end
    
    def store
      @store ||= Hash.new
    end
    
    def reset_data
      store.clear unless store.empty?
    end
    
    def ps_axu
      # TODO: need a mutex here
      store[:ps_axu] ||= begin
        # BSD style ps invocation
        lines = `ps axo pid=,ppid=,pcpu=,rss=`.split("\n")

        lines.inject(Hash.new) do |mem, line| 
          chunks = line.split(/\s+/)
          chunks.delete_if {|c| c.strip.empty? }
          pid = chunks[IDX_MAP[:pid]].strip.to_i
          mem[pid] = chunks
          mem
        end
      end
    end
    
    # be sure to call this from a fork otherwise it will modify the attributes
    # of the bluepill daemon
    def drop_privileges(uid, gid)
      uid_num = Etc.getpwnam(uid).uid if uid
      gid_num = Etc.getgrnam(gid).gid if gid

      ::Process.groups = [gid_num] if gid
      ::Process::Sys.setgid(gid_num) if gid
      ::Process::Sys.setuid(uid_num) if uid
    end
    
    def can_write_pid_file(pid_file, logger)
      FileUtils.touch(pid_file)
      File.unlink(pid_file)
      return true
      
    rescue Exception => e
      logger.warning "%s - %s" % [e.class.name, e.message]
      e.backtrace.each {|l| logger.warning l}
      return false
    end
  end
end