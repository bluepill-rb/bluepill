# frozen_string_literal: true

require "tmpdir"

# A process with a null logger, a fixed clock, and the journal, signals,
# commands and pid file deletion stubbed, plus helpers that record what
# it does
RSpec.shared_context "with a process" do
  subject(:process) do
    described_class.new(:proc_name, [], logger:)
  end

  let(:logger) { instance_double(Bluepill::Logger).as_null_object }
  let(:now) { 1_000_000 }
  # The journals of every process, children too
  let(:journal) { instance_double(Bluepill::ProcessJournal::Journal, append: nil, kill_all: nil) }

  before do
    allow(Bluepill::Clock).to receive(:now).and_return(now)
    allow(Bluepill::ProcessJournal).to receive(:for).and_return(journal)
    allow(::Process).to receive(:kill).and_return(1)
    allow(Bluepill::System).to receive(:execute_blocking).and_return(succeeded)
    allow(Bluepill::System).to receive(:delete_if_exists)
  end

  # The result of a command that succeeded
  def succeeded = Bluepill::System::CommandResult.new(exit_code: 0)

  def watch_double(name, events)
    instance_double(
      Bluepill::ConditionWatch,
      name.to_s,
      name:,
      due?: true,
      run: events,
      to_s: name.to_s,
      clear_history!: nil
    )
  end

  # Give the process pid 5, which signal 0 finds running, since
  # ::Process.kill is stubbed
  def run_process = process.actual_pid = 5

  # A thread left over from an earlier command, which clean_threads kills
  def leftover_thread
    thread = instance_double(Thread, kill: nil)
    process.instance_variable_get(:@threads) << thread
    thread
  end

  # The events dispatched to the process, with their reasons
  def dispatched_events
    process.statistics.events.collect { |event, reason, _time| [event, reason] }
  end

  # The threads the process starts from now on, so an example can wait for
  # the hooks they run
  def capture_threads
    threads = []
    allow(Thread).to receive(:new).and_wrap_original do |new_thread, *args, &block|
      thread = new_thread.call(*args, &block)
      threads << thread
      thread
    end
    threads
  end

  # Record, in order, the signals sent with their pids, the journal
  # cleanups, the pid file deletions and the commands run. Signal 0 finds
  # the process running until it has been sent alive times.
  def record_calls(alive = nil)
    calls = record_signals(alive)
    allow(journal).to receive(:kill_all) { calls << :cleanup }
    allow(Bluepill::System).to receive(:delete_if_exists) { calls << :unlink }
    allow(Bluepill::System).to receive(:execute_blocking) { |command, _options| succeeded.tap { calls << command } }
    calls
  end

  # Record the signals sent, with their pids. Signal 0 finds the process
  # running until it has been sent alive times.
  def record_signals(alive)
    calls = []
    allow(::Process).to receive(:kill) do |signal, pid|
      calls << [signal, pid]
      raise Errno::ESRCH if signal == 0 && alive && (alive -= 1) < 0

      1
    end
    calls
  end

  # Record the threads the commands run on
  def record_command_threads
    threads = []
    allow(Bluepill::System).to receive(:execute_blocking) { succeeded.tap { threads << Thread.current } }
    threads
  end

  # Record the pids added to the journal from now on
  def record_journal
    journaled = []
    allow(journal).to receive(:append) { |pid| journaled << pid }
    journaled
  end

  # Record the messages logged at a level from now on
  def record_log(level)
    messages = []
    allow(logger).to receive(level) { |message| messages << message }
    messages
  end
end
