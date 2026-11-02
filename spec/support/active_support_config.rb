# frozen_string_literal: true

# A config that loads ActiveSupport before bluepill, as one that loads a
# Rails app does, so 10.seconds is an ActiveSupport::Duration. Run by
# spec/configs_spec.rb, which expects it to print "ok".
require "bundler/setup"
require "logger"
require "active_support"
require "active_support/core_ext/numeric"
require "bluepill"

# The flapping check below leaves trigger threads that are killed when
# the script ends, and JRuby 9.2 reports a killed thread as one that
# died with an exception, after "ok"
Thread.report_on_exception = false

def check(description)
  raise "#{description} failed" unless yield
end

check("ActiveSupport keeps its own durations") { 10.seconds.is_a?(ActiveSupport::Duration) }

logger = Bluepill::Logger.new(logger: Logger.new(nil))

# A check that runs every 10 seconds
watch = Bluepill::ConditionWatch.new(:always_true, every: 10.seconds, logger: logger)
check("a watch runs the first time") { watch.run(1, 100).empty? }
check("a watch waits out its interval") { watch.run(1, 105).equal?(Bluepill::ConditionWatch::EMPTY_ARRAY) }
check("a watch runs again after its interval") { watch.run(1, 110).empty? }

# Memory below 100 megabytes, of a process using 1,024 kilobytes
check("a memory limit") { Bluepill::ProcessConditions::MemUsage.new(below: 100.megabytes).check?(1024.0) }
check("a running time limit") { Bluepill::ProcessConditions::RunningTime.new(below: 24.hours).check?(60) }

# Grace times, stop signals and their delays
factory = Bluepill::ProcessFactory.new(
  {
    start_command: "/bin/true",
    pid_file: "/tmp/bluepill_active_support.pid",
    start_grace_time: 2.seconds,
    stop_grace_time: 40.seconds,
    stop_signals: [:quit, 30.seconds, :kill]
  },
  proc {}
)
process, = factory.create_process("active_support", "/tmp")
process.logger = logger
process.skip_ticks_for(process.start_grace_time)
check("a grace time skips ticks") { process.skip_ticks_until - Bluepill::Clock.now >= 1 }
check("a timeout of a few seconds") { process.with_timeout(2.seconds, "start") { :done }.equal?(:done) }

# Flapping within 30 seconds, retrying in 7
flapping = Bluepill::Triggers::Flapping.new(process, times: 2, within: 30.seconds, retry_in: 7.seconds, logger: logger)
starting = Struct.new(:to_name).new(:starting)
flapping.notify(starting)
halted = catch(:halt) do
  flapping.notify(starting)
  :not_halted
end
check("flapping within 30 seconds") { halted.nil? }
# (The unmonitor it schedules too runs at once, and may be gone already.)
check("flapping retries in 7 seconds") { flapping.scheduled_events.collect(&:first).include?(:start) }
flapping.reset!

puts "ok"
