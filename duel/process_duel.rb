# frozen_string_literal: true

require_relative "duel_helper"

# Every second, the application ticks each process: its state machine
# checks that it's still running (signal 0 to its pid), and then it runs
# its watches. These processes have no watches, which run on threads of
# their own (see watch_duel.rb), and their pid is the worker's own, so
# they stay up.
duel "tick: an up process" do
  once { @process = up_process("web", ::Process.pid) }
  @process.tick
end

duel "tick: a group of 10 up processes" do
  once do
    @group = Bluepill::Group.new("web", logger: process_logger)
    10.times { |i| @group.add_process(up_process("web-#{i}", ::Process.pid)) }
  end
  @group.tick
end

# What `bluepill status` shows
duel "status: a group of 10 processes" do
  once do
    @group = Bluepill::Group.new("web", logger: process_logger)
    10.times { |i| @group.add_process(up_process("web-#{i}", 50_000 + i)) }
  end
  @group.status
end

duel "status: a process with its event history" do
  once do
    @group = Bluepill::Group.new("web", logger: process_logger)
    process = up_process("web-0", 50_000)
    10.times { process.statistics.record_event(:restart, "mem_usage: [1.2GB*, 1.3GB*, 1.3GB*]") }
    @group.add_process(process)
  end
  @group.status("web-0")
end

# Each process keeps its last 10 events, which status shows
duel "history: record a process event" do
  once do
    @statistics = Bluepill::ProcessStatistics.new
    10.times { @statistics.record_event(:start, "user initiated") }
  end
  @statistics.record_event(:restart, "mem_usage")
end

# Every check logs its history each time it runs, through the process's
# logger, which adds the app's and the process's names
duel "log: a message with app and process prefixes" do
  once { @logger = process_logger }
  @logger.info("mem_usage: [312MB, 318MB, 322MB, 330MB, 341MB]")
end

duel "log: a message without prefixes" do
  once { @logger = Bluepill::Logger.new(logger: NullLog.new) }
  @logger.info("mem_usage: [312MB, 318MB, 322MB, 330MB, 341MB]")
end
