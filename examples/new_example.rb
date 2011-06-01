require 'rubygems'
require 'bluepill'
require 'logger'

# Note that this syntax supported from bluepill 0.0.50

ROOT_DIR = "/tmp/bp"

# Watch with
# watch -n0.2 'ps axu | egrep "(CPU|forking|bluepill|sleep)" | grep -v grep | sort'
Bluepill.application(:sample_app) do
  0.times do |i|
    process("process_#{i}") do
      pid_file "#{ROOT_DIR}/pids/process_#{i}.pid"

      # Example of use of pid_command option to find memcached process
      # pid_command = "ps -ef | awk '/memcached$/{ print $2 }'"

      # I could not figure out a portable way to
      # specify the path to the sample forking server across the diff developer laptops.
      # Since this code is eval'ed we cannot reliably use __FILE__
      start_command "/Users/rohith/work/bluepill/bin/sample_forking_server #{4242 + i}"
      stop_command "kill -INT {{PID}}"
      daemonize!

      start_grace_time 1.seconds
      restart_grace_time 7.seconds
      stop_grace_time 7.seconds

      uid "rohith"
      gid "staff"

      # checks :cpu_usage, :every => 10, :below => 0.5, :times => [5, 5]
      checks :flapping, :times => 2, :within => 30.seconds, :retry_in => 7.seconds

      monitor_children do
        # checks :cpu_usage,
        #   :every => 10,
        #   :below => 0.5,
        #   :times => [5, 5]

        # checks :mem_usage,
        #   :every => 3,
        #   :below => 600.kilobytes,
        #   :times => [3, 5],
        #   :fires => [:stop]

        stop_command "kill -QUIT {{PID}}"
        # checks :flapping, :times => 2, :within => 30.seconds, :retry_in => 7.seconds
      end
    end
  end

  0.times do |i|
    process("group_process_#{i}") do
      group "group_1"
      pid_file "/Users/rohith/ffs/tmp/pids/mongrel_#{i}.pid"
      start_command "cd ~/ffs && mongrel_rails start -P #{pid_file} -p 3000 -d"

      start_grace_time 10.seconds

      uid "rohith"
      gid "staff"

      # checks :always_true, :every => 10
    end
  end

  1.times do |i|
    process("group_process_#{i}") do
      auto_start false

      uid "rohith"
      gid "wheel"

      stderr "/tmp/err.log"
      stdout "/tmp/err.log"


      group "grouped"
      start_command %Q{cd /tmp && ruby -e '$stderr.puts("hello stderr");$stdout.puts("hello stdout"); $stdout.flush; $stderr.flush; sleep 10'}
      daemonize!
      pid_file "/tmp/noperm/p_#{group}_#{i}.pid"

      # checks :always_true, :every => 5
    end
  end
end

