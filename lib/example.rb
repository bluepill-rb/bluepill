require 'rubygems'
require 'bluepill'
require 'logger'

ROOT_DIR = "/tmp/bp"

# Watch with 
# watch -n0.2 'ps axu | egrep "(CPU|forking|bluepill|sleep)" | grep -v grep | sort'
Bluepill.application(:sample_app) do |app|
  1.times do |i|
    app.process("process_#{i}") do |process|
      process.pid_file = "#{ROOT_DIR}/pids/process_#{i}.pid"
      
      # I could not figure out a portable way to
      # specify the path to the sample forking server across the diff developer laptops.
      # Since this code is eval'ed we cannot reliably use __FILE__
      process.start_command = "/Users/rohith/work/bluepill/bin/sample_forking_server #{4242 + i}"
      process.stop_command = "kill -INT {{PID}}"
      process.daemonize = true
      
      process.start_grace_time = 1.seconds
      process.restart_grace_time = 7.seconds
      process.stop_grace_time = 7.seconds
      
      process.uid = "rohith"
      process.gid = "staff"
      
      # process.checks :cpu_usage, :every => 10, :below => 0.5, :times => [5, 5]
      process.checks :flapping, :times => 2, :within => 30.seconds, :retry_in => 7.seconds
      
      process.monitor_children do |child_process|
        # child_process.checks :cpu_usage, 
        #   :every => 10, 
        #   :below => 0.5, 
        #   :times => [5, 5]
        
        # child_process.checks :mem_usage, 
        #   :every => 3, 
        #   :below => 600.kilobytes, 
        #   :times => [3, 5], 
        #   :fires => [:stop]
        
        child_process.stop_command = "kill -QUIT {{PID}}"
        # child_process.checks :flapping, :times => 2, :within => 30.seconds, :retry_in => 7.seconds
      end
    end
  end
  
  0.times do |i|
    app.process("group_process_#{i}") do |process|
      process.group = "group_1"
      process.pid_file = "/Users/rohith/ffs/tmp/pids/mongrel_#{i}.pid"
      process.start_command = "cd ~/ffs && mongrel_rails start -P #{process.pid_file} -p 3000 -d"
      
      process.start_grace_time = 10.seconds
      
      process.uid = "rohith"
      process.gid = "staff"
      
      # process.checks :always_true, :every => 10
    end
  end
  
  1.times do |i|
    app.process("group_process_#{i}") do |process|
      process.group = "grouped"
      process.start_command = %Q{cd /tmp && ruby -e '$stderr.puts("hello stderr");$stdout.puts("hello stdout"); sleep 10' 1>> /tmp/err.log 2>&1 }
      process.daemonize = true
      process.pid_file = "#{ROOT_DIR}/pids/process_#{process.group}_#{i}.pid"
      
      # process.checks :always_true, :every => 5
    end
  end
end