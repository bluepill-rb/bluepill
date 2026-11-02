# frozen_string_literal: true

# Shared by the benchmarks in duel/. Bluepill runs ps once a tick and
# answers every watch from its table, so the benchmarks give it a fixed
# ps listing instead of the machine's own, which changes from moment to
# moment.

# A ps listing (`ps -Ao pid,ppid,pcpu,rss,etime,args`) of the given number
# of processes. It has init, an app server's master, its workers, and
# their children (grandchildren of the master), and other processes
# make up the rest. Seeded, so every worker gets the same listing.
def ps_listing(processes, workers: 0, grandchildren: 0)
  @ps_listings ||= {}
  @ps_listings[[processes, workers, grandchildren]] ||= begin
    random = Random.new(42)
    rows = [[1, 0, "0.0", 11_204, "45-02:13:07", "/sbin/init"]]
    rows << [PsListing::MASTER, 1, "0.4", 98_816, "12-04:31:55", "unicorn master -c /srv/app/config/unicorn.rb -E production -D"]
    worker_pids = Array.new(workers) { |i| PsListing::MASTER + 1 + i }
    worker_pids.each_with_index do |pid, i|
      rows << [pid, PsListing::MASTER, format("%.1f", random.rand(40.0)), 180_000 + random.rand(60_000), "03:12:09", "unicorn worker[#{i}] -c /srv/app/config/unicorn.rb -E production -D"]
    end
    grandchildren.times do |i|
      rows << [PsListing::MASTER + 1000 + i, worker_pids.fetch(i % workers), "0.0", 2_048, "00:41", "sh -c convert /tmp/upload#{i}.png"]
    end
    pid = 100
    while rows.length < processes
      program = PsListing::PROGRAMS.fetch(random.rand(PsListing::PROGRAMS.length))
      rows << [pid, 1, format("%.1f", random.rand(5.0)), random.rand(400_000), PsListing::ELAPSED.fetch(random.rand(PsListing::ELAPSED.length)), program]
      pid += 1 + random.rand(7)
    end
    lines = rows.collect { |row| format("%7d %7d %5s %8d %12s %s", *row) }
    "    PID    PPID  %CPU      RSS      ELAPSED COMMAND\n#{lines.join("\n")}\n"
  end
end

module PsListing
  MASTER = 50_000
  PROGRAMS = [
    "/usr/sbin/sshd -D",
    "sshd: deploy@pts/0",
    "-bash",
    "/usr/sbin/cron -f",
    "/usr/lib/postgresql/16/bin/postgres -D /var/lib/postgresql/16/main -c config_file=/etc/postgresql/16/main/postgresql.conf",
    "postgres: 16/main: checkpointer",
    "nginx: worker process",
    "/usr/bin/redis-server 127.0.0.1:6379",
    "[kworker/3:1-events]",
    "/lib/systemd/systemd-journald",
    "ruby /srv/app/bin/sidekiq -e production -C config/sidekiq.yml"
  ].freeze
  ELAPSED = %w[00:03 12:41 03:12:09 1-07:22:41 45-02:13:07].freeze

  class << self
    attr_accessor :output
  end
end

# Bluepill runs ps with backticks. In the benchmarks, it reads the listing
# that PsListing.output holds instead.
Bluepill::System.define_singleton_method(:`) { |_command| PsListing.output }

# The ps table Bluepill would make of a listing
def ps_table(listing)
  PsListing.output = listing
  Bluepill::System.reset_data
  Bluepill::System.ps_axu
ensure
  Bluepill::System.reset_data
end

# A logger that drops what bluepill writes to it, so the benchmarks time
# bluepill's own logging (the prefixes and formatting) and not syslog
class NullLog
  Bluepill::Logger::LOG_METHODS.each do |method|
    define_method(method) { |_message| nil }
  end
end

# The hooks of a benchmark that reads the ps table of a listing: it makes
# the table once, and puts it in place of ps's before every sample, since
# other benchmarks in the worker put theirs there too
def table_hooks(processes, **listing)
  {
    setup: -> { @table = ps_table(ps_listing(processes, **listing)) },
    before_sample: -> { Bluepill::System.store[:ps_axu] = @table }
  }
end

# The logger a process gets: the app's, prefixed with the app's name and
# then the process's
def process_logger
  Bluepill::Logger.new(logger: NullLog.new).prefix_with("app").prefix_with("web")
end

# The hooks of a benchmark of a check of the app server's master, among
# 300 processes. The watch has a full history, as it does after its first
# few intervals. It runs every 10 seconds, so each run passes it the tick
# 10 seconds after the last.
def watch_hooks(check, options)
  {
    setup: lambda do
      @table = ps_table(ps_listing(300, workers: 4))
      Bluepill::System.store[:ps_axu] = @table
      @tick = 0
      @watch = Bluepill::ConditionWatch.new(check, options.merge(every: 10.seconds, logger: process_logger))
      10.times { run_watch }
    end,
    before_sample: -> { Bluepill::System.store[:ps_axu] = @table }
  }
end

def run_watch
  @watch.run(PsListing::MASTER, @tick += 10)
end

# A process that's up, with the given pid
def up_process(name, pid)
  process = Bluepill::Process.new(name, {}, logger: process_logger, actual_pid: pid)
  process.state = "up"
  process
end
