#!/bin/bash
# Runs bluepill for real, as a daemon and in the foreground, on the Ruby
# that `ruby` is: loads a pill, checks status, restarts a process with a
# stop_command, runs a hook that times out, and quits. Prints a FAIL line
# for each check that fails, and exits 1 if any did.
cd "$(dirname "$0")/.." || exit 1
dir=$(mktemp -d /tmp/bp.XXXXXX)
failures=0
bluepill() { ruby -Ilib bin/bluepill --no-privileged -c "$dir/base" "$@"; }
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }
# Wait up to 60 seconds for a command to succeed, since JRuby starts slowly
wait_for() { for _ in $(seq 1 120); do eval "$1" && return 0; sleep 0.5; done; return 1; }
alive() { [ -s "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

cat > "$dir/smoke.pill" <<RUBY
Bluepill.application("smoke", log_file: "$dir/bluepill.log", foreground: ENV["SMOKE_FOREGROUND"] == "1") do |app|
  app.process("sleeper") do |process|
    process.start_command = "sleep 600"
    process.pid_file = "$dir/sleeper.pid"
    process.daemonize = true
    process.stdout = process.stderr = "$dir/sleeper.log"
    process.environment = {"SMOKE" => "1"}
    process.working_dir = "$dir"
    process.stop_command = "kill -TERM {{PID}}"
    process.pre_start_command = "touch $dir/pre_start"
    process.post_stop_command = "sleep 600"
    process.hook_timeout = 2
    process.start_grace_time = 5
    process.stop_grace_time = 5
    process.restart_grace_time = 10
  end
end
RUBY

run() {
  mode=$1
  rm -rf "$dir/base" "$dir"/*.pid "$dir/pre_start"
  mkdir -p "$dir/base"
  if [ "$mode" = foreground ]; then
    SMOKE_FOREGROUND=1 bluepill load "$dir/smoke.pill" > "$dir/foreground.log" 2>&1 &
  else
    check "$mode: load returns" "bluepill load '$dir/smoke.pill' > /dev/null 2>&1"
  fi
  check "$mode: the daemon writes its pid file" "wait_for \"alive '$dir/base/pids/smoke.pid'\""
  check "$mode: the process starts" "wait_for \"alive '$dir/sleeper.pid'\""
  check "$mode: the pre_start_command runs" "wait_for \"[ -e '$dir/pre_start' ]\""
  check "$mode: status says up" "wait_for \"bluepill status 2>&1 | grep -q 'sleeper.*up'\""
  first=$(cat "$dir/sleeper.pid")
  pgid() { ps -o pgid= -p "$1" | tr -d ' '; }
  check "$mode: the process isn't in the daemon's process group" \
    "[ \"\$(pgid $first)\" != \"\$(pgid \$(cat '$dir/base/pids/smoke.pid'))\" ]"
  check "$mode: restart" "bluepill restart sleeper > /dev/null 2>&1"
  check "$mode: the process restarts with a new pid" "wait_for \"alive '$dir/sleeper.pid' && [ \\\"\\\$(cat '$dir/sleeper.pid')\\\" != $first ]\""
  check "$mode: the old process stopped" "! kill -0 $first 2>/dev/null"
  check "$mode: the hook that runs too long is killed" "wait_for \"grep -q 'took longer than 2 seconds' '$dir/bluepill.log'\""
  second=$(cat "$dir/sleeper.pid")
  kill -KILL "$second"
  check "$mode: a process that dies is started again" "wait_for \"alive '$dir/sleeper.pid' && [ \\\"\\\$(cat '$dir/sleeper.pid')\\\" != $second ]\""
  daemon=$(cat "$dir/base/pids/smoke.pid")
  sleeper=$(cat "$dir/sleeper.pid")
  check "$mode: quit" "bluepill quit > /dev/null 2>&1"
  check "$mode: the daemon exits" "wait_for \"! kill -0 $daemon 2>/dev/null\""
  kill "$sleeper" 2>/dev/null
  wait 2>/dev/null
}

ruby -v
run daemon
run foreground
if [ $failures -gt 0 ]; then
  echo "--- bluepill.log"; tail -40 "$dir/bluepill.log"
  [ -s "$dir/foreground.log" ] && { echo "--- foreground output"; tail -20 "$dir/foreground.log"; }
fi
pkill -f "$dir" 2>/dev/null
rm -rf "$dir"
echo "$failures failures"
[ $failures -eq 0 ]
