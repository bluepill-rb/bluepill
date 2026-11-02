require "tmpdir"

describe Bluepill::Process do
  subject(:process) do
    described_class.new(:proc_name, [], logger: logger)
  end

  let(:logger) { instance_double(Bluepill::Logger).as_null_object }
  let(:now) { Time.at(1_000_000) }

  before do
    allow(Time).to receive(:now).and_return(now)
    allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal)
    allow(Bluepill::ProcessJournal).to receive(:append_pid_to_journal)
    allow(::Process).to receive(:kill).and_return(1)
    allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 0)
    allow(Bluepill::System).to receive(:delete_if_exists)
  end

  def watch_double(name, events)
    instance_double(Bluepill::ConditionWatch, name.to_s, :name => name, :due? => true, :run => events, :to_s => name.to_s, :clear_history! => nil, :logger= => nil)
  end

  # Give the process pid 5, which signal 0 finds running, since
  # ::Process.kill is stubbed
  def run_process
    process.actual_pid = 5
  end

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
    calls = []
    allow(::Process).to receive(:kill) do |signal, pid|
      calls << [signal, pid]
      raise Errno::ESRCH if signal == 0 && alive && (alive -= 1) < 0

      1
    end
    allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal) { calls << :cleanup }
    allow(Bluepill::System).to receive(:delete_if_exists) { calls << :unlink }
    allow(Bluepill::System).to receive(:execute_blocking) { |command, _options| {exit_code: 0}.tap { calls << command } }
    calls
  end

  # Record the threads the commands run on
  def record_command_threads
    threads = []
    allow(Bluepill::System).to receive(:execute_blocking) { {exit_code: 0}.tap { threads << Thread.current } }
    threads
  end

  # Record the names and pids added to the journal from now on
  def record_journal
    journaled = []
    allow(Bluepill::ProcessJournal).to receive(:append_pid_to_journal) { |name, pid| journaled << [name, pid] }
    journaled
  end

  # Record the messages logged at a level from now on
  def record_log(level)
    messages = []
    allow(logger).to receive(level) { |message| messages << message }
    messages
  end

  describe "#initialize" do
    describe "defaults" do
      [
        :start_command, :stop_command, :restart_command, :stdout, :stderr, :stdin,
        :daemonize, :pid_file, :working_dir, :uid, :gid, :child_process_factory,
        :pid_command, :auto_start, :supplementary_groups, :stop_signals,
        :post_start_command, :pre_stop_command, :post_stop_command, :notify_command,
        :app_name, :group_name
      ].each do |attr|
        it "leaves ##{attr} unset" do
          expect(process.public_send(attr)).to be_nil
        end
      end

      {
        monitor_children: false,
        hook_timeout: 30,
        cache_actual_pid: true,
        start_grace_time: 3,
        stop_grace_time: 3,
        restart_grace_time: 3,
        on_start_timeout: "start",
        environment: {},
        state: "unmonitored",
        group_start_noblock: true,
        group_stop_noblock: true,
        group_restart_noblock: true,
        group_unmonitor_noblock: true
      }.each do |attr, value|
        it "sets ##{attr} to #{value.inspect}" do
          expect(process.public_send(attr)).to eq value
        end
      end
    end

    context "without options" do
      subject(:process) { described_class.new(:proc_name, []) }

      it "has its name, no children and no events" do
        expect(process).to have_attributes(
          name: :proc_name,
          children: [],
          statistics: be_a(Bluepill::ProcessStatistics).and(have_attributes(events: []))
        )
      end

      it "has no threads, and a monitor for its events" do
        expect([:@threads, :@event_mutex].collect { |name| process.instance_variable_get(name) }).to match [[], be_a(Monitor)]
      end
    end

    describe "overrides" do
      subject(:process) { described_class.new(:proc_name, [], start_grace_time: 17) }

      it "sets an option it is given" do
        expect(process.start_grace_time).to eq 17
      end
    end

    context "with checks" do
      subject(:process) do
        described_class.new(:proc_name, {flapping: {times: 2}, mem_usage: {below: 100, every: 10}}, logger: logger)
      end

      it "adds a trigger for a trigger check" do
        expect(process.triggers).to match [be_a(Bluepill::Triggers::Flapping).and(have_attributes(logger: logger, times: 2, process: process))]
      end

      it "adds a watch for every other check" do
        expect(process.watches).to match [have_attributes(name: :mem_usage, logger: logger)]
      end

      it "gives the watch its options" do
        expect(process.watches.first.instance_variable_get(:@every)).to eq 10
      end

      it "propagates a new logger to watches and triggers" do
        new_logger = instance_double(Bluepill::Logger).as_null_object
        process.logger = new_logger
        expect([process, process.watches.first, process.triggers.first].collect(&:logger)).to all(be new_logger)
      end
    end

    it "accepts an actual pid" do
      process = described_class.new(:proc_name, [], logger: logger, actual_pid: 42)
      expect(process.actual_pid).to eq 42
    end
  end

  describe "#tick" do
    let(:thread) { leftover_thread }
    let(:watch) { watch_double(:w, []) }
    let(:child) { instance_double(described_class, "child", tick: nil) }

    before { process.watches << watch }

    context "when skipping ticks" do
      before do
        process.skip_ticks_until = now.to_i + 10
        thread
        process.tick
      end

      it "leaves threads alone" do
        expect(thread).not_to have_received(:kill)
      end

      it "keeps skipping them" do
        expect(process.skip_ticks_until).to eq now.to_i + 10
      end
    end

    context "when the process stopped since it was last found running" do
      before do
        process.state = "up"
        run_process
        process.process_running = true
        allow(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH)
        process.tick
      end

      it "runs no watches" do
        expect(watch).not_to have_received(:run)
      end

      it "is down" do
        expect(process).to be_down
      end
    end

    context "when unmonitored" do
      before do
        process.skip_ticks_until = now.to_i - 1
        thread
        process.tick
      end

      it "cleans threads" do
        expect(thread).to have_received(:kill)
      end

      it "stops skipping ticks" do
        expect(process.skip_ticks_until).to be_nil
      end

      it "stays unmonitored" do
        expect(process).to be_unmonitored
      end
    end

    it "leaves threads alone when the process is monitored" do
      process.state = "up"
      run_process
      thread
      process.tick
      expect(thread).not_to have_received(:kill)
    end

    context "when down and not running" do
      before do
        process.state = "down"
        process.start_command = "start-cmd"
        process.tick
      end

      it "starts the process" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("start-cmd", anything)
      end

      it "runs no watches" do
        expect(watch).not_to have_received(:run)
      end

      it "transitions to starting" do
        expect(process).to be_starting
      end
    end

    context "when down and running" do
      before do
        process.state = "down"
        run_process
        allow(Bluepill::System).to receive(:get_children)
        process.tick
      end

      it "runs watches" do
        expect(watch).to have_received(:run)
      end

      it "looks for no children" do
        expect(Bluepill::System).not_to have_received(:get_children)
      end

      it "transitions to up" do
        expect(process).to be_up
      end
    end

    context "when up and monitoring children" do
      before do
        process.child_process_factory = instance_double(Bluepill::ProcessFactory, create_child_process: child)
        process.state = "up"
        process.monitor_children = true
        run_process
        allow(Bluepill::System).to receive(:get_children).with(5).and_return([7])
        process.tick
      end

      it "finds and ticks children" do
        expect(child).to have_received(:tick)
      end

      it "stays up" do
        expect(process).to be_up
      end
    end

    {
      "starting" => %w[up down],
      "up" => %w[up down],
      "stopping" => %w[up down],
      "restarting" => %w[up down]
    }.each do |from, (running_to, stopped_to)|
      it "transitions from #{from} to #{running_to} when running" do
        process.state = from
        run_process
        process.tick
        expect(process.state).to eq running_to
      end

      it "transitions from #{from} to #{stopped_to} when not running" do
        process.state = from
        process.tick
        expect(process.state).to eq stopped_to
      end
    end
  end

  describe "events" do
    context "with start" do
      before do
        process.start_command = "start-cmd"
        process.dispatch!(:start, "reason")
      end

      it "starts the process" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("start-cmd", anything)
      end

      it "transitions to starting" do
        expect(process).to be_starting
      end

      it "records the event and its reason" do
        expect(process.statistics.events.first[0, 2]).to eq [:start, "reason"]
      end
    end

    context "with an event given as a string" do
      let(:mutex) { process.instance_variable_get(:@event_mutex) }

      before do
        allow(mutex).to receive(:synchronize).and_call_original
        process.dispatch!("start")
      end

      it "handles one event at a time" do
        expect(mutex).to have_received(:synchronize)
      end

      it "fires the event" do
        expect(process).to be_starting
      end
    end

    context "with stop" do
      before do
        process.state = "up"
        run_process
        process.dispatch!(:stop)
      end

      it "stops the process" do
        expect(::Process).to have_received(:kill).with("TERM", 5)
      end

      it "transitions to stopping" do
        expect(process).to be_stopping
      end
    end

    context "with restart" do
      before do
        process.state = "down"
        process.restart_command = "restart-cmd"
        process.dispatch!(:restart)
      end

      it "restarts the process" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("restart-cmd", anything)
      end

      it "transitions to restarting" do
        expect(process).to be_restarting
      end
    end

    context "with unmonitor while stopping" do
      let(:thread) { leftover_thread }

      before do
        process.state = "stopping"
        thread
        process.dispatch!(:unmonitor)
      end

      it "cleans threads" do
        expect(thread).to have_received(:kill)
      end

      it "transitions to unmonitored" do
        expect(process).to be_unmonitored
      end
    end
  end

  describe "#record_transition" do
    let(:watch) { watch_double(:w, []) }

    context "with a loopback" do
      before { process.record_transition(described_class::Transition.new(:up, :up)) }

      it "logs nothing" do
        expect(logger).not_to have_received(:info)
      end

      it "records no transition" do
        expect(process.instance_variable_get(:@transitioned)).to be_nil
      end
    end

    context "with a change of state" do
      before do
        process.watches << watch
        process.record_transition(described_class::Transition.new(:up, :down))
      end

      it "clears watch history" do
        expect(watch).to have_received(:clear_history!)
      end

      it "logs the change" do
        expect(logger).to have_received(:info).with("Going from up => down")
      end

      it "leaves children alone when not monitoring them" do
        expect(logger).not_to have_received(:warning)
      end

      it "records the transition" do
        expect(process.instance_variable_get(:@transitioned)).to be true
      end
    end

    context "when monitoring children" do
      before do
        process.monitor_children = true
        process.children << instance_double(described_class, "child")
        process.record_transition(described_class::Transition.new(:up, :down))
      end

      it "logs that it clears the child list" do
        expect(logger).to have_received(:warning).with("Clearing child list")
      end

      it "clears the child list" do
        expect(process.children).to be_empty
      end
    end
  end

  describe "#notify_triggers" do
    let(:transition) { described_class::Transition.new(:up, :down) }
    let(:trigger) { instance_double(Bluepill::Trigger, "trigger", :logger= => nil, :notify => nil) }
    let(:error) { RuntimeError.new("boom").tap { |e| e.set_backtrace(%w[a b]) } }

    before { process.triggers << trigger }

    def notify_and_rescue
      process.notify_triggers(transition)
    rescue RuntimeError
      nil
    end

    it "notifies each trigger" do
      process.notify_triggers(transition)
      expect(trigger).to have_received(:notify).with(transition)
    end

    it "re-raises errors" do
      allow(trigger).to receive(:notify).and_raise(error)
      expect { process.notify_triggers(transition) }.to raise_error(error)
    end

    it "logs errors" do
      allow(trigger).to receive(:notify).and_raise(error)
      notify_and_rescue
      expect(logger).to have_received(:err).with(%w[a b])
    end
  end

  describe "#add_watch" do
    it "adds a condition watch" do
      process.add_watch(:mem_usage, below: 10)
      expect(process.watches).to match [be_a(Bluepill::ConditionWatch).and(have_attributes(logger: logger))]
    end
  end

  describe "#run_watches" do
    before { process.actual_pid = 5 }

    context "with a quiet and a loud watch" do
      let(:quiet) { watch_double(:quiet, []) }
      let(:loud) { watch_double(:loud, [:restart, :stop]) }

      before do
        allow(loud).to receive(:to_s).and_return("loud: [1, 2]")
        process.watches << quiet << loud
        process.run_watches
      end

      it "logs the events a watch dispatches" do
        expect(logger).to have_received(:info).once.with("loud dispatched: restart,stop")
      end

      it "logs nothing for a watch that dispatches nothing" do
        expect(logger).not_to have_received(:info).with("quiet dispatched: ")
      end

      it "runs the watches with the pid and the time" do
        expect(quiet).to have_received(:run).with(5, now.to_i)
      end

      it "dispatches events from watches" do
        expect(dispatched_events).to eq [[:restart, "loud: [1, 2]"], [:stop, "loud: [1, 2]"]]
      end
    end

    context "with a watch that is not due" do
      let(:idle) { watch_double(:idle, [:restart]) }

      before do
        allow(idle).to receive(:due?).with(now.to_i).and_return(false)
        allow(Thread).to receive(:new).and_call_original
        process.watches << idle
        process.run_watches
      end

      it "does not run it" do
        expect(idle).not_to have_received(:run)
      end

      it "does not start a thread for it" do
        expect(Thread).not_to have_received(:new)
      end
    end

    # A tick with no watch due has nothing to wait for or dispatch, so it
    # returns before it resets the transition
    it "returns early when no watch is due" do
      process.instance_variable_set(:@transitioned, true)
      process.watches << watch_double(:idle, [:restart]).tap { |idle| allow(idle).to receive(:due?).and_return(false) }
      process.run_watches
      expect(process.instance_variable_get(:@transitioned)).to be(true)
    end

    it "dispatches after a transition in an earlier run" do
      process.instance_variable_set(:@transitioned, true)
      process.watches << watch_double(:loud, [:restart])
      process.run_watches
      expect(dispatched_events).to eq [[:restart, "loud"]]
    end

    it "stops dispatching after a transition" do
      process.state = "down"
      process.watches << watch_double(:loud, [:start, :stop])
      process.run_watches
      expect(dispatched_events).to eq [[:start, "loud"]]
    end
  end

  describe "#determine_initial_state" do
    it "is up when running" do
      run_process
      process.determine_initial_state
      expect(process.state).to eq "up"
    end

    it "checks again, even if the process was running earlier in the tick" do
      process.process_running = true
      process.determine_initial_state
      expect(process.state).to eq "down"
    end

    it "is unmonitored when auto_start is false" do
      process.auto_start = false
      process.determine_initial_state
      expect(process.state).to eq "unmonitored"
    end

    it "is down otherwise" do
      process.determine_initial_state
      expect(process.state).to eq "down"
    end
  end

  describe "#handle_user_command" do
    context "with start for a running process" do
      before do
        run_process
        process.handle_user_command("start")
      end

      it "refuses to start it" do
        expect(logger).to have_received(:warning).with("Refusing to re-run start command on an already running process.")
      end

      it "dispatches nothing" do
        expect(dispatched_events).to be_empty
      end
    end

    it "starts a stopped process" do
      process.handle_user_command("start")
      expect(dispatched_events).to eq [[:start, "user initiated"]]
    end

    it "checks again before starting, even if the process was running earlier in the tick" do
      process.process_running = true
      process.handle_user_command("start")
      expect(dispatched_events).to eq [[:start, "user initiated"]]
    end

    context "with stop" do
      before do
        process.state = "up"
        run_process
        process.handle_user_command("stop")
      end

      it "stops the process" do
        expect(::Process).to have_received(:kill).with("TERM", 5)
      end

      it "unmonitors it" do
        expect(dispatched_events).to eq [[:unmonitor, "user initiated"]]
      end
    end

    context "with restart for an up process" do
      before do
        process.state = "up"
        process.restart_command = "restart-cmd"
        process.handle_user_command("restart")
      end

      it "restarts through the state machine" do
        expect(dispatched_events).to eq [[:restart, "user initiated"]]
      end

      it "restarts it once" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("restart-cmd", anything).once
      end

      it "goes to restarting" do
        expect(process.state).to eq("restarting")
      end
    end

    context "with restart from a state restart cannot leave" do
      before do
        process.state = "unmonitored"
        process.restart_command = "restart-cmd"
        process.handle_user_command("restart")
      end

      it "restarts directly" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("restart-cmd", anything).once
      end

      it "stays in its state" do
        expect(process.state).to eq("unmonitored")
      end
    end

    context "with unmonitor" do
      let(:trigger) { instance_double(Bluepill::Trigger, "trigger", :logger= => nil, :notify => nil, :reset! => nil) }

      before do
        process.triggers << trigger
        process.handle_user_command("unmonitor")
      end

      it "resets triggers" do
        expect(trigger).to have_received(:reset!)
      end

      it "unmonitors" do
        expect(dispatched_events).to eq [[:unmonitor, "user initiated"]]
      end
    end

    it "returns nil for an unknown command" do
      expect(process.handle_user_command("bogus")).to be_nil
    end

    it "ignores unknown commands" do
      process.handle_user_command("bogus")
      expect(dispatched_events).to be_empty
    end
  end

  describe "predicates" do
    it "are false, not nil, for unset attributes" do
      process.cache_actual_pid = nil
      process.monitor_children = nil
      expect([process.cache_actual_pid?, process.monitor_children?, process.daemonize?]).to eq [false, false, false]
    end

    it "are true, not the attribute, for set attributes" do
      process.cache_actual_pid = 1
      process.monitor_children = 1
      process.daemonize = 1
      expect([process.cache_actual_pid?, process.monitor_children?, process.daemonize?]).to eq [true, true, true]
    end
  end

  describe "#process_running?" do
    before { process.actual_pid = 5 }

    it "is true, and stays true, for a running process" do
      expect(Array.new(2) { process.process_running? }).to eq [true, true]
    end

    it "memoizes a running result" do
      2.times { process.process_running? }
      expect(::Process).to have_received(:kill).once.with(0, 5)
    end

    it "keeps the pid of a running process" do
      process.process_running?
      expect(process.actual_pid).to eq 5
    end

    it "rechecks when forced" do
      process.process_running?
      process.process_running?(true)
      expect(::Process).to have_received(:kill).twice.with(0, 5)
    end

    context "when not running" do
      before { allow(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH) }

      it "is false" do
        expect(process.process_running?).to be false
      end

      it "clears the pid" do
        process.process_running?
        expect(process.instance_variable_get(:@actual_pid)).to be_nil
      end
    end
  end

  describe "#start_process" do
    before { process.start_command = "/etc/init.d/script start" }

    context "with the start command" do
      before do
        allow(Timeout).to receive(:timeout).and_call_original
        process.start_process
      end

      it "logs the start command" do
        expect(logger).to have_received(:warning).with("Executing start command: /etc/init.d/script start")
      end

      it "runs the start command with the process options" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("/etc/init.d/script start", process.system_command_options)
      end

      it "gives the start command start_grace_time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end

      it "skips ticks for start_grace_time" do
        expect(process.skip_ticks_until).to eq now.to_i + 3
      end
    end

    it "dispatches on_start_timeout when the start command takes too long" do
      process.on_start_timeout = "unmonitor"
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.start_process
      expect(dispatched_events).to eq [["unmonitor", nil]]
    end

    it "runs the pre start command first" do
      process.pre_start_command = "prepare"
      calls = record_calls
      process.start_process
      expect(calls).to eq [:cleanup, "prepare", "/etc/init.d/script start"]
    end

    it "warns on a non-zero exit code" do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      warnings = record_log(:warning)
      process.start_process
      expect(warnings).to include("Start command execution returned non-zero exit code:", {exit_code: 1}.inspect)
    end

    it "warns when a signal killed the command" do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: nil)
      warnings = record_log(:warning)
      process.start_process
      expect(warnings).to include("Start command execution returned non-zero exit code:", {exit_code: nil}.inspect)
    end

    context "with a stop signal thread left from an earlier stop" do
      let(:stop_thread) { Thread.new { sleep } }

      before do
        process.instance_variable_get(:@threads) << stop_thread
        process.start_process
      end

      it "kills the thread" do
        stop_thread.join(1)
        expect(stop_thread).not_to be_alive
      end

      it "forgets the thread" do
        expect(process.instance_variable_get(:@threads)).to be_empty
      end
    end

    context "when daemonizing" do
      before do
        process.daemonize = true
        allow(Bluepill::System).to receive(:daemonize).and_return(99)
      end

      it "kills what earlier runs left" do
        process.start_process
        expect(Bluepill::ProcessJournal).to have_received(:kill_all_from_journal).with(:proc_name)
      end

      it "daemonizes the start command with the process options" do
        process.start_process
        expect(Bluepill::System).to have_received(:daemonize).with("/etc/init.d/script start", process.system_command_options)
      end

      it "journals the daemon pid" do
        process.start_process
        expect(Bluepill::ProcessJournal).to have_received(:append_pid_to_journal).with(:proc_name, 99)
      end

      it "journals children pids when monitoring children" do
        process.monitor_children = true
        process.children << instance_double(described_class, "child", actual_pid: 100)
        journaled = record_journal
        process.start_process
        expect(journaled).to eq [[:proc_name, 99], [:proc_name, 100]]
      end

      it "does not journal when daemonizing fails" do
        allow(Bluepill::System).to receive(:daemonize).and_return(nil)
        process.start_process
        expect(Bluepill::ProcessJournal).not_to have_received(:append_pid_to_journal)
      end
    end
  end

  describe "#pre_start_process" do
    it "does nothing without a pre start command" do
      process.pre_start_process
      expect(Bluepill::System).not_to have_received(:execute_blocking)
    end

    context "with a pre start command" do
      before { process.pre_start_command = "prepare" }

      it "logs only that it runs it" do
        warnings = record_log(:warning)
        process.pre_start_process
        expect(warnings).to eq ["Executing pre start command: prepare"]
      end

      it "runs it with the process options" do
        process.pre_start_process
        expect(Bluepill::System).to have_received(:execute_blocking).with("prepare", process.system_command_options)
      end

      it "warns on a non-zero exit code" do
        allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 2)
        process.pre_start_process
        expect(logger).to have_received(:warning).with("Pre start command execution returned non-zero exit code:")
      end
    end
  end

  describe "#stop_process" do
    before { process.actual_pid = 5 }

    context "with a stop command" do
      before do
        process.stop_command = "/etc/init.d/script stop"
        allow(Timeout).to receive(:timeout).and_call_original
        process.stop_process
      end

      it "runs the stop command with the process options" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("/etc/init.d/script stop", process.system_command_options)
      end

      it "gives the stop command stop_grace_time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end
    end

    it "dispatches stop when the stop command takes too long" do
      process.stop_command = "/etc/init.d/script stop"
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.stop_process
      expect(dispatched_events).to eq [["stop", nil]]
    end

    context "with a stop command that fails" do
      let(:warnings) { record_log(:warning) }

      before do
        process.stop_command = "kill {{PID}}; wait {{PID}}"
        process.pid_file = "some.pid"
        allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
        allow(Bluepill::System).to receive(:get_children)
        warnings
        process.stop_process
      end

      it "logs the command with the pid, and warns of the exit code" do
        expect(warnings.first(2)).to eq ["Executing stop command: kill 5; wait 5", "Stop command execution returned non-zero exit code:"]
      end

      it "looks for no children when not monitoring them" do
        expect(Bluepill::System).not_to have_received(:get_children)
      end

      it "cleans up the journal" do
        expect(Bluepill::ProcessJournal).to have_received(:kill_all_from_journal).with(:proc_name)
      end

      it "deletes the pid file" do
        expect(Bluepill::System).to have_received(:delete_if_exists).with("some.pid")
      end

      it "substitutes the pid" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("kill 5; wait 5", anything)
      end
    end

    context "when monitoring children" do
      before { process.monitor_children = true }

      it "journals children" do
        allow(Bluepill::System).to receive(:get_children).with(5).and_return([6, 7])
        journaled = record_journal
        process.stop_process
        expect(journaled).to eq [[:proc_name, 6], [:proc_name, 7]]
      end

      it "journals no children when stopped before it has a pid" do
        process.clear_pid
        allow(Bluepill::System).to receive(:ps_axu).and_return(0 => %w[PID PPID %CPU RSS ELAPSED COMMAND])
        journaled = record_journal
        process.stop_process
        expect(journaled).to be_empty
      end
    end

    context "without a stop command or stop signals" do
      before { process.stop_process }

      it "logs that it sends TERM" do
        expect(logger).to have_received(:warning).with("Executing default stop command. Sending TERM signal to 5")
      end

      it "sends TERM" do
        expect(::Process).to have_received(:kill).with("TERM", 5)
      end

      it "deletes the pid file" do
        expect(Bluepill::System).to have_received(:delete_if_exists).with(nil)
      end

      it "skips ticks for stop_grace_time" do
        expect(process.skip_ticks_until).to eq now.to_i + 3
      end
    end

    context "with stop signals" do
      # The seconds the process sleeps for, between stop signals and while it
      # waits for the process to exit
      let(:sleeps) { [] }

      before { allow(Kernel).to receive(:sleep) { |seconds| sleeps << seconds } }

      def run_stop_signals(signals, grace_time = 3)
        process.stop_signals = signals
        process.stop_grace_time = grace_time
        process.stop_process
        process.instance_variable_get(:@threads).each(&:join)
      end

      it "sends a single signal, and waits for it" do
        calls = record_calls
        run_stop_signals([:quit])
        expect(calls).to eq [["QUIT", 5], [0, 5], :cleanup, :unlink]
      end

      it "logs that it sends stop signals" do
        run_stop_signals([:quit])
        expect(logger).to have_received(:warning).with("Sending stop signals to 5")
      end

      it "cleans up the journal of the process" do
        run_stop_signals([:quit])
        expect(Bluepill::ProcessJournal).to have_received(:kill_all_from_journal).with(:proc_name)
      end

      it "sends each signal while the process is alive" do
        calls = record_calls
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(calls).to eq [["QUIT", 5], [0, 5], ["TERM", 5], [0, 5], ["KILL", 5], :cleanup, :unlink]
      end

      it "logs each signal" do
        infos = record_log(:info)
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(infos).to eq ["Sending signal quit to 5", "Sending signal term to 5", "Sending signal kill to 5"]
      end

      it "logs each delay" do
        debugs = record_log(:debug)
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(debugs).to eq ["Sleeping for 2 seconds", "Sleeping for 3 seconds"]
      end

      it "waits for each delay" do
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(sleeps).to eq [2, 3]
      end

      it "leaves the stop signals as they were" do
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(process.stop_signals).to eq [:quit, 2, :term, 3, :kill]
      end

      it "stops once the process has terminated" do
        calls = record_calls(0)
        run_stop_signals([:quit, 2, :kill])
        expect(calls).to eq [["QUIT", 5], [0, 5], :cleanup, :unlink]
      end

      it "logs that the process has terminated" do
        record_calls(0)
        run_stop_signals([:quit, 2, :kill])
        expect(logger).to have_received(:debug).with("Process has terminated.")
      end

      it "checks a fractional wait in whole seconds, rounded up" do
        calls = record_calls
        run_stop_signals([:quit], 4.5)
        expect(calls).to eq [["QUIT", 5], [0, 5], [0, 5], [0, 5], :cleanup, :unlink]
      end

      it "rounds a fractional wait up to whole seconds" do
        run_stop_signals([:quit], 4.5)
        expect(sleeps).to eq [1, 1, 1]
      end

      it "waits for the process to exit before cleaning up" do
        calls = record_calls
        run_stop_signals([:quit], 5)
        expect(calls).to eq [["QUIT", 5], [0, 5], [0, 5], [0, 5], :cleanup, :unlink]
      end

      it "waits a second between checks" do
        run_stop_signals([:quit], 5)
        expect(sleeps).to eq [1, 1, 1]
      end

      it "cleans up as soon as the process exits after the last signal" do
        calls = record_calls(2)
        run_stop_signals([:quit, 2, :term], 10)
        expect(calls).to eq [["QUIT", 5], [0, 5], ["TERM", 5], [0, 5], [0, 5], :cleanup, :unlink]
      end

      it "stops waiting as soon as the process exits after the last signal" do
        record_calls(2)
        run_stop_signals([:quit, 2, :term], 10)
        expect(sleeps).to eq [2, 1]
      end
    end
  end

  describe "#restart_process" do
    context "with a restart command" do
      before do
        process.restart_command = "/etc/init.d/script restart"
        allow(Timeout).to receive(:timeout).and_call_original
        process.restart_process
      end

      it "runs the restart command with the process options" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("/etc/init.d/script restart", process.system_command_options)
      end

      it "gives the restart command restart_grace_time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end

      it "skips ticks for restart_grace_time" do
        expect(process.skip_ticks_until).to eq now.to_i + 3
      end
    end

    it "dispatches restart when the restart command takes too long" do
      process.restart_command = "/etc/init.d/script restart"
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.restart_process
      expect(dispatched_events).to eq [["restart", nil]]
    end

    context "with a restart command that fails" do
      before do
        process.restart_command = "restart {{PID}}"
        run_process
        allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      end

      it "logs the command with the pid, and warns of the exit code" do
        warnings = record_log(:warning)
        process.restart_process
        expect(warnings.first(2)).to eq ["Executing restart command: restart 5", "Restart command execution returned non-zero exit code:"]
      end

      it "substitutes the pid" do
        process.restart_process
        expect(Bluepill::System).to have_received(:execute_blocking).with("restart 5", anything)
      end
    end

    context "without a restart command" do
      before do
        run_process
        process.start_command = "start-cmd"
      end

      it "logs that it stops and starts" do
        process.restart_process
        expect(logger).to have_received(:warning).with("No restart_command specified. Must stop and start to restart")
      end

      it "stops and starts" do
        calls = record_calls
        process.restart_process
        expect(calls).to eq [["TERM", 5], :cleanup, :unlink, :cleanup, "start-cmd"]
      end

      it "waits for the stop signals to finish before starting" do
        # A real delay, and a grace time that leaves nothing to wait for after
        # the last signal
        process.stop_signals = [:quit, 0.1, :kill]
        process.stop_grace_time = 2
        calls = record_calls
        process.restart_process
        expect(calls).to eq [["QUIT", 5], [0, 5], ["KILL", 5], :cleanup, :unlink, :cleanup, "start-cmd"]
      end
    end
  end

  describe "#clean_threads" do
    let(:thread) { leftover_thread }

    before do
      thread
      process.clean_threads
    end

    it "kills threads" do
      expect(thread).to have_received(:kill)
    end

    it "clears threads" do
      expect(process.instance_variable_get(:@threads)).to be_empty
    end
  end

  describe "#signal_process" do
    before { process.actual_pid = 5 }

    # Send a signal, and return whether signal_process sent it, with the
    # signals and pids it gave ::Process.kill
    def signal_and_kills(code)
      kills = []
      allow(::Process).to receive(:kill) { |*args| kills << args }
      [process.signal_process(code), kills]
    end

    it "upcases string signals" do
      expect(signal_and_kills("hup")).to eq [true, [["HUP", 5]]]
    end

    it "upcases strings of a String subclass" do
      expect(signal_and_kills(Class.new(String).new("hup"))).to eq [true, [["HUP", 5]]]
    end

    it "turns symbol signals into upcased strings" do
      expect(signal_and_kills(:hup)).to eq [true, [["HUP", 5]]]
    end

    it "signals pid 1" do
      process.actual_pid = 1
      expect(signal_and_kills(0)).to eq [true, [[0, 1]]]
    end

    it "passes integer signals through" do
      expect(signal_and_kills(9)).to eq [true, [[9, 5]]]
    end

    context "when the signal fails" do
      before { allow(::Process).to receive(:kill).and_raise(Errno::EPERM) }

      it "returns false" do
        expect(process.signal_process(0)).to be false
      end

      it "logs the failure" do
        process.signal_process(0)
        expect(logger).to have_received(:err).with(/Failed to signal process 5 with code 0/)
      end
    end

    [0, -1].each do |pid|
      it "never signals pid #{pid}" do
        process.instance_variable_set(:@actual_pid, pid)
        expect(signal_and_kills(0)).to eq [false, []]
      end

      it "logs that pid #{pid} is invalid" do
        process.instance_variable_set(:@actual_pid, pid)
        process.signal_process(0)
        expect(logger).to have_received(:err).with("Failed to signal process #{pid} with code 0: invalid pid #{pid}")
      end
    end

    it "returns false, without signaling, when there is no pid" do
      process.instance_variable_set(:@actual_pid, nil)
      expect(signal_and_kills(0)).to eq [false, []]
    end

    it "logs no error when there is no pid" do
      process.instance_variable_set(:@actual_pid, nil)
      process.signal_process(0)
      expect(logger).not_to have_received(:err)
    end
  end

  describe "#actual_pid" do
    it "uses the pid command when configured" do
      process.pid_command = "echo 123"
      expect(process.actual_pid).to eq 123
    end

    it "returns nil when the pid command prints 0" do
      process.pid_command = "echo 0"
      expect(process.actual_pid).to be_nil
    end

    it "returns nil when the pid command output is not a number" do
      process.pid_command = "echo oops"
      expect(process.actual_pid).to be_nil
    end

    it "returns nil when the pid command output only starts with a number" do
      process.pid_command = "echo 12 oops"
      expect(process.actual_pid).to be_nil
    end

    it "ignores whitespace and leading zeros around the pid command output" do
      process.pid_command = "echo '  0123'"
      expect(process.actual_pid).to eq 123
    end

    it "is nil without a pid file" do
      expect(process.actual_pid).to be_nil
    end

    context "with a pid file" do
      let(:dir) { Dir.mktmpdir }

      before { process.pid_file = File.join(dir, "proc.pid") }

      after { FileUtils.remove_entry(dir) }

      # Write each content to the pid file in turn, and read the pid after
      # each
      def read_pids(*contents)
        contents.collect do |content|
          File.write(process.pid_file, content)
          process.actual_pid
        end
      end

      it "reads the pid and caches it" do
        expect(read_pids("77\n", "78\n")).to eq [77, 77]
      end

      it "deletes the pid file when it cleans up after a stop" do
        allow(Bluepill::System).to receive(:delete_if_exists).and_call_original
        read_pids("77\n")
        process.cleanup_process
        expect(File.exist?(process.pid_file)).to be false
      end

      it "forgets the cached pid when it cleans up after a stop" do
        allow(Bluepill::System).to receive(:delete_if_exists).and_call_original
        before_cleanup = read_pids("77\n")
        process.cleanup_process
        expect(before_cleanup + read_pids("78\n")).to eq [77, 78]
      end

      it "rereads the pid when not caching" do
        process.cache_actual_pid = false
        expect(read_pids("77\n", "78\n")).to eq [77, 78]
      end

      it "is nil for an empty pid file" do
        File.write(process.pid_file, "")
        expect(process.actual_pid).to be_nil
      end

      it "is nil for a pid file that does not hold a positive pid" do
        process.cache_actual_pid = false
        expect(read_pids("0\n", "\n", "garbage", "-5")).to eq [nil, nil, nil, nil]
      end

      it "is not running for a pid file that holds 0" do
        File.write(process.pid_file, "0\n")
        allow(::Process).to receive(:kill).and_call_original
        expect(process.process_running?(true)).to be false
      end

      it "reads pid 1" do
        File.write(process.pid_file, "1\n")
        expect(process.actual_pid).to eq 1
      end

      it "is nil when the pid file does not exist" do
        expect(process.actual_pid).to be_nil
      end

      it "warns when the pid file does not exist" do
        process.actual_pid
        expect(logger).to have_received(:warning).with("pid_file #{process.pid_file} does not exist or cannot be read")
      end
    end
  end

  describe "#actual_pid=" do
    before { process.actual_pid = 12 }

    it "journals the pid" do
      expect(Bluepill::ProcessJournal).to have_received(:append_pid_to_journal).with(:proc_name, 12)
    end

    it "sets the pid" do
      expect(process.actual_pid).to eq 12
    end
  end

  describe "#skip_ticks_for" do
    it "adds to an existing skip" do
      process.skip_ticks_until = now.to_i + 5
      process.skip_ticks_for(2.5)
      expect(process.skip_ticks_until).to eq now.to_i + 7
    end

    it "starts from now without a skip" do
      process.skip_ticks_for(2)
      expect(process.skip_ticks_until).to eq now.to_i + 2
    end
  end

  describe "#refresh_children!" do
    let(:factory) { instance_double(Bluepill::ProcessFactory, "factory") }
    let(:child_logger) { instance_double(Bluepill::Logger, "child logger") }

    before do
      process.actual_pid = 5
      process.child_process_factory = factory
      allow(logger).to receive(:prefix_with).and_return(child_logger)
    end

    context "with dead, living and new children" do
      let(:kids) do
        {
          dead: instance_double(described_class, "dead", actual_pid: 6),
          alive: instance_double(described_class, "alive", actual_pid: 7),
          other: instance_double(described_class, "other", actual_pid: 9, process_running?: true),
          new: instance_double(described_class, "new child")
        }
      end

      before do
        process.children.concat(kids.values_at(:dead, :alive, :other))
        allow(kids[:dead]).to receive(:process_running?).with(true).and_return(false)
        allow(kids[:alive]).to receive(:process_running?).with(true).and_return(true)
        allow(Bluepill::System).to receive(:get_children).with(5).and_return([7, 8, 9])
        allow(factory).to receive(:create_child_process).with("<child(pid:8)>", 8, child_logger).and_return(kids[:new])
        process.refresh_children!
      end

      it "prunes dead children and adds new ones" do
        expect(process.children).to eq kids.values_at(:alive, :other, :new)
      end

      it "logs the children it has and finds" do
        expect(logger).to have_received(:info).with("Existing children: 7,9. Got new children: [8] for 5")
      end

      it "prefixes the new child's logger with its name" do
        expect(logger).to have_received(:prefix_with).with("<child(pid:8)>")
      end

      it "journals no children when not daemonized" do
        expect(Bluepill::ProcessJournal).not_to have_received(:append_pid_to_journal).with(:proc_name, 8)
      end
    end

    it "journals new children when daemonized" do
      process.daemonize = true
      allow(Bluepill::System).to receive(:get_children).and_return([8])
      allow(factory).to receive(:create_child_process).and_return(instance_double(described_class, "child"))
      process.refresh_children!
      expect(Bluepill::ProcessJournal).to have_received(:append_pid_to_journal).with(:proc_name, 8)
    end

    context "without new children" do
      before do
        allow(Bluepill::System).to receive(:get_children).and_return([])
        process.refresh_children!
      end

      it "logs nothing" do
        expect(logger).not_to have_received(:info)
      end

      it "adds no children" do
        expect(process.children).to be_empty
      end
    end
  end

  describe "#with_timeout" do
    let(:block) { proc {} }

    it "returns the result of the block" do
      expect(process.with_timeout(3, "state_override") { :done }).to eq :done
    end

    context "when the block times out" do
      let(:errors) { record_log(:err) }

      before do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
        errors
        process.with_timeout(3, "unmonitor", &block)
      end

      it "logs why it might" do
        expect(errors).to eq ["Execution is taking longer than expected.", "Did you forget to tell bluepill to daemonize this process?"]
      end

      it "gives the block its time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end

      it "proceeds to next_state" do
        expect(dispatched_events).to eq [["unmonitor", nil]]
      end
    end

    it "times out after a fraction of a second" do
      process.with_timeout(0.01, "unmonitor") { Kernel.sleep 1 }
      expect(dispatched_events).to eq [["unmonitor", nil]]
    end
  end

  describe "#system_command_options" do
    subject(:process) { described_class.new(:proc_name, [], options.merge(logger: logger)) }

    let(:options) do
      {
        uid: "user",
        gid: "group",
        working_dir: "/work",
        environment: {"A" => "b"},
        pid_file: "proc.pid",
        stdin: "in",
        stdout: "out",
        stderr: "err",
        supplementary_groups: ["extra"]
      }
    end

    it "passes the process settings to the command" do
      expect(process.system_command_options).to eq options.merge(logger: logger)
    end
  end

  describe "#clear_pid" do
    before do
      process.actual_pid = 5
      process.clear_pid
      process.clear_pid
    end

    it "forgets the pid" do
      expect(process.instance_variable_get(:@actual_pid)).to be_nil
    end

    it "keeps the last pid for notify_command" do
      expect(process.instance_variable_get(:@last_pid)).to eq 5
    end
  end

  describe "#run_hook" do
    let(:options) { process.system_command_options }

    context "with a pid and an environment" do
      before do
        process.environment = {"A" => "1"}
        process.run_hook("renice 20 {{PID}} {{PID}}", "Post start", 7, "B" => "2")
      end

      it "logs the command with the pid" do
        expect(logger).to have_received(:info).with("Executing post start command: renice 20 7 7")
      end

      it "warns of nothing when the command succeeds" do
        expect(logger).not_to have_received(:warning)
      end

      it "runs the command with the pid, and the process's options and environment" do
        expect(Bluepill::System).to have_received(:execute_blocking)
          .with("renice 20 7 7", options.merge(environment: {"A" => "1", "B" => "2"}, timeout: 30))
      end
    end

    it "adds nothing to the environment by default" do
      process.run_hook("drain", "Pre stop", 7)
      expect(Bluepill::System).to have_received(:execute_blocking).with("drain", options.merge(timeout: 30))
    end

    it "runs without an environment of its own" do
      process.environment = nil
      process.run_hook("alert", "Notify", nil, "B" => "2")
      expect(Bluepill::System).to have_received(:execute_blocking).with("alert", hash_including(environment: {"B" => "2"}))
    end

    it "logs a non-zero exit code" do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      process.run_hook("alert", "Notify", 7)
      expect(logger).to have_received(:warning).with("Notify command execution returned non-zero exit code:")
    end

    it "gives the command hook_timeout, and logs one that runs longer" do
      process.hook_timeout = 5
      allow(Bluepill::System).to receive(:execute_blocking).with("drain 7", hash_including(timeout: 5)).and_raise(Timeout::Error)
      process.run_hook("drain {{PID}}", "Pre stop", 7)
      expect(logger).to have_received(:warning).with("Pre stop command took longer than 5 seconds: drain {{PID}}")
    end

    context "with a command that fails to run" do
      before { allow(Bluepill::System).to receive(:execute_blocking).and_raise(Errno::EAGAIN, "fork") }

      it "does not raise" do
        expect { process.run_hook("cleanup", "Post stop", 7) }.not_to raise_error
      end

      it "logs the failure" do
        process.run_hook("cleanup", "Post stop", 7)
        expect(logger).to have_received(:err).with("Post stop command failed: Resource temporarily unavailable - fork")
      end
    end
  end

  describe "#run_hook_in_background" do
    it "runs the hook in a thread of its own" do
      ran_on = record_command_threads
      thread = process.run_hook_in_background("alert", "Notify", 5, "A" => "1")
      thread.join
      expect(ran_on).to eq [thread]
    end

    it "runs the hook with its pid and environment" do
      process.run_hook_in_background("alert {{PID}}", "Notify", 5, "A" => "1").join
      expect(Bluepill::System).to have_received(:execute_blocking).with("alert 5", hash_including(environment: {"A" => "1"}))
    end

    it "logs the hook with its description" do
      process.run_hook_in_background("alert {{PID}}", "Notify", 5, "A" => "1").join
      expect(logger).to have_received(:info).with("Executing notify command: alert 5")
    end

    it "adds nothing to the environment by default" do
      process.environment = {"A" => "1"}
      process.run_hook_in_background("renice", "Post start", 5).join
      expect(Bluepill::System).to have_received(:execute_blocking).with("renice", hash_including(environment: {"A" => "1"}))
    end
  end

  describe "#post_start_process" do
    before do
      process.post_start_command = "renice 20 {{PID}}"
      run_process
    end

    it "does nothing without a post start command" do
      process.post_start_command = nil
      expect(process.post_start_process).to be_nil
    end

    it "runs the post start command with the pid in the background" do
      process.post_start_process.join
      expect(Bluepill::System).to have_received(:execute_blocking).with("renice 20 5", anything)
    end

    it "logs the post start command" do
      process.post_start_process.join
      expect(logger).to have_received(:info).with("Executing post start command: renice 20 5")
    end

    %w[starting restarting].each do |state|
      context "when the process comes up from #{state}" do
        before do
          threads = capture_threads
          process.state = state
          process.tick
          threads.each(&:join)
        end

        it "runs" do
          expect(Bluepill::System).to have_received(:execute_blocking).with("renice 20 5", anything)
        end

        it "is up" do
          expect(process).to be_up
        end
      end
    end

    %w[down up stopping].each do |state|
      it "doesn't run when a process comes back up by itself, or stays up, from #{state}" do
        threads = capture_threads
        process.state = state
        process.tick
        expect(threads).to be_empty
      end
    end
  end

  describe "#pre_stop_process" do
    before { run_process }

    it "runs the pre stop command, and waits for it, before stopping" do
      process.pre_stop_command = "drain {{PID}}"
      calls = record_calls
      process.stop_process
      expect(calls).to eq ["drain 5", ["TERM", 5], :cleanup, :unlink]
    end

    it "runs the pre stop command as Pre stop" do
      process.pre_stop_command = "drain {{PID}}"
      process.stop_process
      expect(logger).to have_received(:info).with("Executing pre stop command: drain 5")
    end

    it "does nothing without a pre stop command" do
      process.stop_process
      expect(Bluepill::System).not_to have_received(:execute_blocking)
    end

    it "logs no failed hook without a pre stop command" do
      process.stop_process
      expect(logger).not_to have_received(:err)
    end
  end

  describe "#post_stop_process" do
    before do
      run_process
      process.post_stop_command = "rm /tmp/{{PID}}.sock"
    end

    it "runs the post stop command after cleaning up" do
      threads = capture_threads
      calls = record_calls
      process.stop_process
      threads.each(&:join)
      expect(calls).to eq [["TERM", 5], :cleanup, :unlink, "rm /tmp/5.sock"]
    end

    it "runs the post stop command in the background" do
      threads = capture_threads
      ran_on = record_command_threads
      process.stop_process
      threads.each(&:join)
      expect(ran_on).to eq threads
    end

    context "when bluepill has forgotten the pid of the process that stopped" do
      before do
        process.post_stop_command = nil
        process.stop_process
        process.clear_pid
        process.post_stop_command = "rm /tmp/{{PID}}.sock"
        process.post_stop_process.join
      end

      it "gives the post stop command that pid" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("rm /tmp/5.sock", anything)
      end

      it "logs the post stop command" do
        expect(logger).to have_received(:info).with("Executing post stop command: rm /tmp/5.sock")
      end
    end

    context "without a post stop command" do
      before { process.post_stop_command = nil }

      it "runs nothing in the background" do
        threads = capture_threads
        process.stop_process
        expect(threads).to be_empty
      end

      it "does nothing" do
        expect(process.post_stop_process).to be_nil
      end
    end
  end

  describe "#notify_transition" do
    let(:transition) { described_class::Transition.new(:up, :restarting) }

    before { process.notify_command = "alert {{PID}}" }

    context "with an app, a group, a pid and a reason" do
      let(:details) do
        {
          "BLUEPILL_APP" => "app",
          "BLUEPILL_GROUP" => "web",
          "BLUEPILL_PROCESS" => "proc_name",
          "BLUEPILL_FROM" => "up",
          "BLUEPILL_TO" => "restarting",
          "BLUEPILL_REASON" => "mem_usage: [1.2GB*]",
          "BLUEPILL_PID" => "5"
        }
      end

      before do
        process.app_name = "app"
        process.group_name = "web"
        run_process
        process.instance_variable_set(:@transition_reason, "mem_usage: [1.2GB*]")
        process.notify_transition(transition).join
      end

      it "runs the notify command in the background, with the details in its environment" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("alert 5", hash_including(environment: details))
      end

      it "logs the notify command" do
        expect(logger).to have_received(:info).with("Executing notify command: alert 5")
      end
    end

    it "gives the last pid of a process that died, and empty values for what it lacks" do
      run_process
      process.clear_pid
      process.notify_transition(transition).join
      expect(Bluepill::System).to have_received(:execute_blocking)
        .with("alert 5", hash_including(environment: hash_including("BLUEPILL_APP" => "", "BLUEPILL_GROUP" => "", "BLUEPILL_REASON" => "", "BLUEPILL_PID" => "5")))
    end

    it "gives no pid before the process has one" do
      process.notify_transition(transition).join
      expect(Bluepill::System).to have_received(:execute_blocking).with("alert ", hash_including(environment: hash_including("BLUEPILL_PID" => "")))
    end

    it "does nothing for a loopback" do
      expect(process.notify_transition(described_class::Transition.new(:up, :up))).to be_nil
    end

    it "does nothing without a notify command" do
      process.notify_command = nil
      expect(process.notify_transition(transition)).to be_nil
    end

    context "when an event changes the state" do
      before do
        threads = capture_threads
        process.state = "up"
        process.dispatch!(:stop, "user initiated")
        threads.each(&:join)
      end

      it "runs, with the event's reason" do
        expect(Bluepill::System).to have_received(:execute_blocking).with(
          "alert ",
          hash_including(environment: hash_including("BLUEPILL_FROM" => "up", "BLUEPILL_TO" => "stopping", "BLUEPILL_REASON" => "user initiated"))
        )
      end

      it "forgets the reason after" do
        expect(process.instance_variable_get(:@transition_reason)).to be_nil
      end
    end

    context "when the transition raises" do
      before do
        process.state = "up"
        allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).and_raise("boom")
      end

      it "raises" do
        expect { process.dispatch!(:stop, "user initiated") }.to raise_error("boom")
      end

      def dispatch_and_rescue
        process.dispatch!(:stop, "user initiated")
      rescue RuntimeError
        nil
      end

      it "forgets the reason even so" do
        dispatch_and_rescue
        expect(process.instance_variable_get(:@transition_reason)).to be_nil
      end
    end
  end
end
