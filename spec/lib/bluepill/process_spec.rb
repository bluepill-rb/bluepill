# frozen_string_literal: true

require_relative "../../support/process_context"

describe Bluepill::Process do
  include_context "with a process"

  describe "#initialize" do
    describe "defaults" do
      %i[
        start_command stop_command restart_command stdout stderr stdin
        daemonize pid_file working_dir uid gid child_process_factory
        pid_command auto_start supplementary_groups stop_signals
        post_start_command pre_stop_command post_stop_command notify_command
        app_name group_name
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
        on_start_timeout: :start,
        environment: {},
        state: :unmonitored,
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
        expect(%i[@threads @event_mutex].collect { |name| process.instance_variable_get(name) }).to match [[], be_a(Monitor)]
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
        described_class.new(:proc_name, {flapping: {times: 2}, mem_usage: {below: 100, every: 10}}, logger:)
      end

      it "adds a trigger for a trigger check" do
        expect(process.triggers).to match [be_a(Bluepill::Triggers::Flapping).and(have_attributes(logger:, times: 2, process:))]
      end

      it "adds a watch for every other check" do
        expect(process.watches).to match [have_attributes(name: :mem_usage, logger:)]
      end

      it "gives the watch its options" do
        expect(process.watches.first.instance_variable_get(:@every)).to eq 10
      end

      it "keeps the logger it gives its watches and triggers" do
        expect([process, process.watches.first, process.triggers.first].collect(&:logger)).to all(be logger)
      end
    end

    context "with checks as a list of names and options" do
      subject(:process) do
        described_class.new(:proc_name, [[:http, {url: "http://a/"}], [:http, {url: "http://b/"}], [:flapping, {}]], logger:)
      end

      it "keeps two checks of the same name" do
        uris = process.watches.collect { |watch| watch.instance_variable_get(:@process_condition).instance_variable_get(:@uri).to_s }
        expect(uris).to eq(%w[http://a/ http://b/])
      end

      it "adds the triggers among them" do
        expect(process.triggers).to match [be_a(Bluepill::Triggers::Flapping)]
      end
    end

    it "refuses a check no class has the name of" do
      expect { described_class.new(:proc_name, {mem_usag: {below: 100}}, logger:) }.to raise_error(Bluepill::ConfigError, /Unknown check 'mem_usag'/)
    end

    it "accepts an actual pid" do
      process = described_class.new(:proc_name, [], logger:, actual_pid: 42)
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
        process.skip_ticks_until = now + 10
        thread
        process.tick
      end

      it "leaves threads alone" do
        expect(thread).not_to have_received(:kill)
      end

      it "keeps skipping them" do
        expect(process.skip_ticks_until).to eq now + 10
      end
    end

    context "when the process stopped since it was last found running" do
      before do
        process.state = :up
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
        process.skip_ticks_until = now - 1
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

      it "logs no error" do
        expect(logger).not_to have_received(:err)
      end
    end

    it "leaves threads alone when the process is monitored" do
      process.state = :up
      run_process
      thread
      process.tick
      expect(thread).not_to have_received(:kill)
    end

    context "when down and not running" do
      before do
        process.state = :down
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
        process.state = :down
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
        process.child_process_factory = instance_double(Bluepill::ProcessFactory::ChildFactory, create_child_process: child)
        process.state = :up
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

    context "when something raises" do
      let(:error) { RuntimeError.new("boom").tap { |e| e.set_backtrace(["line 1", "line 2"]) } }
      let(:errors) { record_log(:err) }

      before do
        errors
        process.state = :up
        run_process
        process.triggers << instance_double(Bluepill::Trigger, "trigger").tap { |t| allow(t).to receive(:notify).and_raise(error) }
      end

      it "logs the error and its backtrace" do
        process.tick
        expect(errors).to eq(["tick failed: RuntimeError: boom", "line 1", "line 2"])
      end

      it "keeps ticking" do
        2.times { process.tick }
        expect(errors.grep(/tick failed/).size).to eq(2)
      end

      it "stays in its state" do
        process.tick
        expect(process).to be_up
      end

      it "lets an error that isn't a StandardError through" do
        allow(process).to receive(:fire_event).and_raise(NoMemoryError)
        expect { process.tick }.to raise_error(NoMemoryError)
      end
    end

    {
      starting: %i[up down],
      up: %i[up down],
      stopping: %i[up down],
      restarting: %i[up down]
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

    context "with an event, one at a time" do
      let(:mutex) { process.instance_variable_get(:@event_mutex) }

      before do
        allow(mutex).to receive(:synchronize).and_call_original
        process.dispatch!(:start)
      end

      it "handles one event at a time" do
        expect(mutex).to have_received(:synchronize)
      end

      it "fires the event" do
        expect(process).to be_starting
      end
    end

    context "with an event that isn't a transition" do
      it "raises a KeyError, without calling a method of that name" do
        allow(process).to receive(:clean_threads).and_raise("called clean_threads")
        expect { process.dispatch!(:clean_threads) }.to raise_error(KeyError)
      end
    end

    context "with stop" do
      before do
        process.state = :up
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
        process.state = :down
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
        process.state = :stopping
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

  describe "#run_watches" do
    before { process.actual_pid = 5 }

    context "with a quiet and a loud watch" do
      let(:quiet) { watch_double(:quiet, []) }
      let(:loud) { watch_double(:loud, %i[restart stop]) }

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
        expect(quiet).to have_received(:run).with(5, now)
      end

      it "dispatches events from watches" do
        expect(dispatched_events).to eq [[:restart, "loud: [1, 2]"], [:stop, "loud: [1, 2]"]]
      end
    end

    context "with a watch that is not due" do
      let(:idle) { watch_double(:idle, [:restart]) }

      before do
        allow(idle).to receive(:due?).with(now).and_return(false)
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
      process.state = :down
      process.watches << watch_double(:loud, %i[start stop])
      process.run_watches
      expect(dispatched_events).to eq [[:start, "loud"]]
    end
  end

  describe "#determine_initial_state" do
    it "is up when running" do
      run_process
      process.determine_initial_state
      expect(process.state).to eq(:up)
    end

    it "checks again, even if the process was running earlier in the tick" do
      process.process_running = true
      process.determine_initial_state
      expect(process.state).to eq(:down)
    end

    it "is unmonitored when auto_start is false" do
      process.auto_start = false
      process.determine_initial_state
      expect(process.state).to eq(:unmonitored)
    end

    it "is down otherwise" do
      process.determine_initial_state
      expect(process.state).to eq(:down)
    end
  end

  describe "#handle_user_command" do
    context "with start for a running process" do
      before do
        run_process
        process.handle_user_command(:start)
      end

      it "refuses to start it" do
        expect(logger).to have_received(:warning).with("Refusing to re-run start command on an already running process.")
      end

      it "dispatches nothing" do
        expect(dispatched_events).to be_empty
      end
    end

    it "starts a stopped process" do
      process.handle_user_command(:start)
      expect(dispatched_events).to eq [[:start, "user initiated"]]
    end

    it "checks again before starting, even if the process was running earlier in the tick" do
      process.process_running = true
      process.handle_user_command(:start)
      expect(dispatched_events).to eq [[:start, "user initiated"]]
    end

    context "with stop" do
      before do
        process.state = :up
        run_process
        process.handle_user_command(:stop)
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
        process.state = :up
        process.restart_command = "restart-cmd"
        process.handle_user_command(:restart)
      end

      it "restarts through the state machine" do
        expect(dispatched_events).to eq [[:restart, "user initiated"]]
      end

      it "restarts it once" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("restart-cmd", anything).once
      end

      it "goes to restarting" do
        expect(process.state).to eq(:restarting)
      end
    end

    context "with restart from a state restart cannot leave" do
      before do
        process.state = :unmonitored
        process.restart_command = "restart-cmd"
        process.handle_user_command(:restart)
      end

      it "restarts directly" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("restart-cmd", anything).once
      end

      it "stays in its state" do
        expect(process.state).to eq(:unmonitored)
      end
    end

    context "with unmonitor" do
      let(:trigger) { instance_double(Bluepill::Trigger, "trigger", notify: nil, reset!: nil) }

      before do
        process.triggers << trigger
        process.handle_user_command(:unmonitor)
      end

      it "resets triggers" do
        expect(trigger).to have_received(:reset!)
      end

      it "unmonitors" do
        expect(dispatched_events).to eq [[:unmonitor, "user initiated"]]
      end
    end

    it "returns nil for an unknown command" do
      expect(process.handle_user_command(:bogus)).to be_nil
    end

    it "ignores unknown commands" do
      process.handle_user_command(:bogus)
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

  describe "#skip_ticks_for" do
    it "adds to an existing skip" do
      process.skip_ticks_until = now + 5
      process.skip_ticks_for(2.5)
      expect(process.skip_ticks_until).to eq now + 7
    end

    it "starts from now without a skip" do
      process.skip_ticks_for(2)
      expect(process.skip_ticks_until).to eq now + 2
    end
  end
end
