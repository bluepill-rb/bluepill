require 'rubygems'
require 'bluepill'
require 'logger'

# ATTENTION:
# You must declare only one application per config when foreground mode specified

# Watch with 
# watch -n0.2 'ps axu | egrep "(CPU|forking|bluepill|sleep)" | grep -v grep | sort'
Bluepill.application(:opscode_agent, :foreground => true) do |app|
  app.process("opscode_agent") do |process|
    process.pid_file = "/etc/service/opscode-agent/supervise/pid"
      
    process.start_command = "sv start opscode-agent"
    process.stop_command = "sv stop opscode-agent"
      
    process.start_grace_time = 1.seconds
    process.restart_grace_time = 7.seconds
    process.stop_grace_time = 7.seconds
      
    # process.checks :cpu_usage, :every => 10, :below => 0.5, :times => [5, 5]
    process.checks :flapping, :times => 2, :within => 30.seconds, :retry_in => 7.seconds
  end
end
