#! /usr/bin/env ruby
require 'rubygems'
require 'bluepill'
require 'logger'

# ATTENTION:
# You must declare only one application per config when foreground mode specified
#
# http://github.com/Undev/runit-man used as example of monitored application.

# Note that this syntax supported from bluepill 0.0.50

Bluepill.application(:runit_man, foreground: true) do
  process('runit-man') do
    pid_file '/etc/service/runit-man/supervise/pid'

    start_command '/usr/bin/sv start runit-man'
    stop_command '/usr/bin/sv stop runit-man'
    restart_command '/usr/bin/sv restart runit-man'

    start_grace_time 1.seconds
    restart_grace_time 7.seconds
    stop_grace_time 7.seconds

    checks :http, within: 30.seconds, retry_in: 7.seconds, every: 30.seconds,
                  url: 'http://localhost:4567/', kind: :success, pattern: /html/, timeout: 3.seconds
  end
end
