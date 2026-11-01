# Monitors sample_forking_server, an echo server with three workers.
#
# Start it from the root of this repository:
#
#   sudo bluepill load examples/sample_app.rb
#   sudo bluepill status
#
# Then send a few lines with `nc localhost 4242`. Each request makes a worker
# use 10 MB more memory, and once a worker stays over 50 MB, bluepill stops
# it and the server starts a new one. Watch it happen with:
#
#   watch -n1 'sudo bluepill status; ps axu | grep [f]orking_server'
#
# Stop everything with:
#
#   sudo bluepill stop
#   sudo bluepill quit

Bluepill.application(:sample_app) do |app|
  app.process('forking_server') do |process|
    process.start_command = "#{File.expand_path('sample_forking_server', File.dirname(__FILE__))} 4242"
    # INT stops the server and its workers right away
    process.stop_command = 'kill -INT {{PID}}'
    process.pid_file = '/tmp/bluepill_sample_app.pid'
    process.daemonize = true
    process.stdout = process.stderr = '/tmp/bluepill_sample_app.log'

    process.start_grace_time = 3.seconds
    process.stop_grace_time = 5.seconds
    process.restart_grace_time = 8.seconds

    # Give up for a while if the server keeps dying right after it starts
    process.checks :flapping, times: 2, within: 30.seconds, retry_in: 7.seconds

    process.monitor_children do |child|
      # QUIT lets a worker finish what it's doing before it exits
      child.stop_command = 'kill -QUIT {{PID}}'
      # Stop a worker that's over 50 MB in 3 of the last 5 checks
      child.checks :mem_usage, every: 3.seconds, below: 50.megabytes, times: [3, 5], fires: :stop
    end
  end
end
