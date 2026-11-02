# frozen_string_literal: true

# ATTENTION:
# You must declare only one application per config when foreground mode specified
#
# https://github.com/Undev/runit-man used as example of monitored application.

Bluepill.application(:runit_man, foreground: true) do |app|
  app.process("runit-man") do |process|
    process.pid_file = "/etc/service/runit-man/supervise/pid"

    process.start_command = "/usr/bin/sv start runit-man"
    process.stop_command = "/usr/bin/sv stop runit-man"
    process.restart_command = "/usr/bin/sv restart runit-man"

    process.start_grace_time = 1.seconds
    process.restart_grace_time = 7.seconds
    process.stop_grace_time = 7.seconds

    process.checks :http, every: 30.seconds,
      url: "http://localhost:4567/", kind: :success, pattern: /html/, timeout: 3.seconds
  end
end
