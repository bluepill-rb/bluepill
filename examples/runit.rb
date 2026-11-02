# frozen_string_literal: true

# Monitors a web server that runit supervises as the service web, in
# /etc/service/web. Bluepill starts, stops and restarts it with sv, reads
# its pid from runit's supervise directory, and restarts it when its home
# page stops answering.
#
# It runs in the foreground, so runit can supervise bluepill too, from a
# service whose run script is:
#
#   exec bluepill load /path/to/runit.rb
#
# A config in foreground mode defines only one application.

Bluepill.application(:web, foreground: true) do |app|
  app.process("web") do |process|
    process.pid_file = "/etc/service/web/supervise/pid"

    process.start_command = "/usr/bin/sv start web"
    process.stop_command = "/usr/bin/sv stop web"
    process.restart_command = "/usr/bin/sv restart web"

    process.start_grace_time = 1.seconds
    process.restart_grace_time = 7.seconds
    process.stop_grace_time = 7.seconds

    process.checks :http, every: 30.seconds,
      url: "http://localhost:8080/", kind: :success, pattern: /html/, timeout: 3.seconds
  end
end
