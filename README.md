# Bluepill
Bluepill is a simple process monitoring tool written in Ruby.

[![Gem Version](https://badge.fury.io/rb/bluepill.svg)][gem]
[![Build Status](https://github.com/bluepill-rb/bluepill/actions/workflows/ci.yml/badge.svg?branch=master)][ci]
[![Maintainability](https://qlty.sh/gh/bluepill-rb/projects/bluepill/maintainability.svg)][qlty]
[![Coverage Status](https://coveralls.io/repos/github/bluepill-rb/bluepill/badge.svg?branch=master)][coveralls]
[![Duel](https://raw.githubusercontent.com/sferik/duel-ruby/main/assets/badge.svg)](https://github.com/sferik/duel-ruby)

[gem]: https://rubygems.org/gems/bluepill
[ci]: https://github.com/bluepill-rb/bluepill/actions/workflows/ci.yml
[qlty]: https://qlty.sh/gh/bluepill-rb/projects/bluepill
[coveralls]: https://coveralls.io/github/bluepill-rb/bluepill?branch=master

## Installation
It&apos;s hosted on [rubygems.org][rubygems].

    sudo gem install bluepill

In order to take advantage of logging with syslog, you also need to setup your syslog to log the local6 facility. Edit the appropriate config file for your syslogger (/etc/syslog.conf for syslog) and add a line for local6:

    local6.*          /var/log/bluepill.log

You&apos;ll also want to add _/var/log/bluepill.log_ to _/etc/logrotate.d/syslog_ so that it gets rotated.

Lastly, create the _/var/run/bluepill_ directory for bluepill to store its pid and sock files.

## Usage
### Config
Bluepill organizes processes into 3 levels: application -> group -> process. Each process has a few attributes that tell bluepill how to start, stop, and restart it, where to look or put the pid file, what process conditions to monitor and the options for each of those.

The minimum config file looks something like this:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
  end
end
```

Note that since we specified a PID file and start command, bluepill assumes the process will daemonize itself. If we wanted bluepill to daemonize it for us, we can do (note we still need to specify a PID file):

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.daemonize = true
  end
end
```

If you don&apos;t specify a stop command, a TERM signal will be sent by default. Similarly, the default restart action is to issue stop and then start.

Now if we want to do something more meaningful, like actually monitor the process, we do:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.checks :cpu_usage, every: 10.seconds, below: 5, times: 3
  end
end
```

We added a line that checks every 10 seconds to make sure the cpu usage of this process is below 5 percent; 3 failed checks results in a restart. We can specify a two-element array for the _times_ option to say that it 3 out of 5 failed attempts results in a restart.

To watch memory usage, we just add one more line:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.checks :cpu_usage, every: 10.seconds, below: 5, times: 3
    process.checks :mem_usage, every: 10.seconds, below: 100.megabytes, times: [3,5]
  end
end
```

To watch the modification time of a file, e.g. a log file to ensure the process is actually working add one more line:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.checks :cpu_usage, every: 10.seconds, below: 5, times: 3
    process.checks :mem_usage, every: 10.seconds, below: 100.megabytes, times: [3,5]
    process.checks :file_time, every: 60.seconds, below: 3.minutes, filename: "/tmp/some_file.log", times: 2
  end
end
```

To restart process if it's running too long:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.checks :running_time, every: 10.minutes, below: 24.hours
  end
end
```

We can tell bluepill to give a process some grace time to start/stop/restart before resuming monitoring:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.start_grace_time = 3.seconds
    process.stop_grace_time = 5.seconds
    process.restart_grace_time = 8.seconds
    process.checks :cpu_usage, every: 10.seconds, below: 5, times: 3
    process.checks :mem_usage, every: 10.seconds, below: 100.megabytes, times: [3,5]
  end
end
```

We can group processes by name:

```ruby
Bluepill.application("app_name") do |app|
  5.times do |i|
    app.process("process_name_#{i}") do |process|
      process.group = "mongrels"
      process.start_command = "/usr/bin/some_start_command"
      process.pid_file = "/tmp/some_pid_file.pid"
    end
  end
end
```

If you want to run the process as someone other than root:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.uid = "deploy"
    process.gid = "deploy"
    process.checks :cpu_usage, every: 10.seconds, below: 5, times: 3
    process.checks :mem_usage, every: 10.seconds, below: 100.megabytes, times: [3,5]
  end
end
```

If you want to include one or more supplementary groups:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.uid = "deploy"
    process.gid = "deploy"
    process.supplementary_groups = ['rvm']
    process.checks :cpu_usage, every: 10.seconds, below: 5, times: 3
    process.checks :mem_usage, every: 10.seconds, below: 100.megabytes, times: [3,5]
  end
end
```

You can also set an app-wide uid/gid:

```ruby
Bluepill.application("app_name") do |app|
  app.uid = "deploy"
  app.gid = "deploy"
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
  end
end
```

To track resources of child processes, use `:include_children`:
```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.checks :mem_usage, every: 1.seconds, below: 5.megabytes, times: [3,5], include_children: true
  end
end
```

To check for flapping:

```ruby
process.checks :flapping, times: 2, within: 30.seconds, retry_in: 7.seconds
```

To set the working directory to `cd` into when starting the command:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.working_dir = "/path/to/some_directory"
  end
end
```

You can also have an app-wide working directory:

```ruby
Bluepill.application("app_name") do |app|
  app.working_dir = "/path/to/some_directory"
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
  end
end
```

Note: We also set the PWD in the environment to the working dir you specify. This is useful for when the working dir is a symlink. Unicorn in particular will cd into the environment variable in PWD when it re-execs to deal with a change in the symlink.

To run a command before every start, for example to clear a cache:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.pre_start_command = "/usr/bin/some_setup_command"
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
  end
end
```

Bluepill waits for the `pre_start_command` to finish, and logs a warning if it exits with a non-zero status, but starts the process either way. It runs in the same `working_dir`, with the same `environment`, `uid`, and `gid`, as the process.

By default, bluepill will send a SIGTERM to your process when stopping.
To change the stop command:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.stop_command = "/user/bin/some_stop_command"
  end
end
```

If you'd like to send a signal or signals to your process to stop it:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.stop_signals = [:quit, 30.seconds, :term, 5.seconds, :kill]
  end
end
```

We added a line that will send a SIGQUIT, wait 30 seconds and check to
see if the process is still up, send a SIGTERM, wait 5 seconds and check
to see if the process is still up, and finally send a SIGKILL.

And lastly, to monitor child processes:

```ruby
process.monitor_children do |child_process|
  child_process.checks :cpu_usage, every: 10, below: 5, times: 3
  child_process.checks :mem_usage, every: 10, below: 100.megabytes, times: [3, 5]
  child_process.stop_command = "kill -QUIT {{PID}}"
end
```

Note {{PID}} will be substituted for the pid of process in both the stop and restart commands.

### Commands Don't Run in a Shell

Bluepill splits each command (`start_command`, `pre_start_command`, `stop_command`, and `restart_command`) into words and runs it directly, without a shell. So shell syntax like `cd ... &&`, `VAR=value`, `|`, `>`, `2>&1`, and `*` globs doesn't work.

Use the config options instead:

```ruby
Bluepill.application("app_name") do |app|
  app.process("process_name") do |process|
    process.start_command = "/usr/bin/some_start_command"
    process.working_dir = "/tmp/some_dir"
    process.environment = {"SOME_VAR" => "1"}
    process.stdout = process.stderr = "/tmp/server.log"
    process.pid_file = "/tmp/some_pid_file.pid"
    process.daemonize = true
  end
end
```

`stdout`, `stderr`, and `stdin` only apply to processes that bluepill daemonizes. A daemonized process starts in `/` unless you set `working_dir`, so use absolute paths or set `working_dir`.

If you really need a shell, run one explicitly, and use `exec` so bluepill monitors your server instead of the shell that started it:

```ruby
process.start_command = "sh -c 'exec /usr/bin/some_start_command < /tmp/input'"
```

### CLI

#### Usage

    bluepill [app_name] command [options]

For the "load" command, the _app_name_ is specified in the config file, and
must not be provided on the command line.

For all other commands, the _app_name_ is optional if there is only
one bluepill daemon running. Otherwise, the _app_name_ must be
provided, because the command will fail when there are multiple
bluepill daemons running. The example commands below leaves out the
_app_name_.

#### Commands

To start a bluepill daemon and load the config for an application:

    sudo bluepill load /path/to/production.pill

To act on a process or group for an application:

    sudo bluepill <start|stop|restart|unmonitor> <process_or_group_name>

To view process statuses for an application:

    sudo bluepill status

To view the log for a process or group for an application:

    sudo bluepill log <process_or_group_name>

To quit the bluepill daemon for an application:

    sudo bluepill quit

#### bpsv

`bpsv` runs a bluepill command on the process it's named after, so a
symlink to it works like an init script. For a process named `unicorn`:

    sudo ln -s "$(which bpsv)" /usr/local/bin/unicorn
    sudo unicorn restart

That runs `bluepill restart unicorn`. Like `bluepill` without an
_app_name_, it only works when one bluepill daemon is running.

### Examples

[examples/sample_app.rb](examples/sample_app.rb) monitors a small forking
echo server, and stops any worker that uses too much memory. Its comments
show how to run it. [examples/runit.rb](examples/runit.rb) monitors a
service managed by runit.

### Logging
By default, bluepill uses syslog local6 facility as described in the installation section. But if for any reason you don&apos;t want to use syslog, you can use a log file. You can do this by setting the :log\_file option in the config:

```ruby
Bluepill.application("app_name", log_file: "/path/to/bluepill.log") do |app|
  # ...
end
```

Keep in mind that you still need to set up log rotation (described in the installation section) to keep the log file from growing huge.

### Foreground mode

You can run bluepill in the foreground:

```ruby
Bluepill.application("app_name", foreground: true) do |app|
  # ...
end
```

Note that You must define only one application per config when using foreground mode.


JRuby allows you to run bluepill only in the foreground.

## Links

* Code: [http://github.com/bluepill-rb/bluepill](http://github.com/bluepill-rb/bluepill)
* Bugs/Features: [http://github.com/bluepill-rb/bluepill/issues](http://github.com/bluepill-rb/bluepill/issues)
* Mailing List: [http://groups.google.com/group/bluepill-rb](http://groups.google.com/group/bluepill-rb)

[rubygems]: http://rubygems.org/gems/bluepill

## Supported Ruby Versions
This library aims to support and is [tested against][ci] the following Ruby
implementations:

* Ruby 1.9.3
* Ruby 2.0 through 2.7
* Ruby 3.0 through 3.4
* Ruby 4.0
* JRuby 1.7 (only in the foreground)
* JRuby 9.0 through 9.4 (only in the foreground)
* JRuby 10.0 and 10.1 (only in the foreground)

If something doesn't work on one of these interpreters, please open an issue.

This library may inadvertently work (or seem to work) on other Ruby
implementations, however support will only be provided for the versions listed
above.

If you would like this library to support another Ruby version, you may
volunteer to be a maintainer. Being a maintainer entails making sure all tests
run and pass on that implementation. When something breaks on your
implementation, you will be responsible for providing patches in a timely
fashion. If critical issues for a particular implementation exist at the time
of a major release, support for that Ruby version may be dropped.
