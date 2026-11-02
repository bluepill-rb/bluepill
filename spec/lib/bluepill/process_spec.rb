require 'tmpdir'

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
    instance_double(Bluepill::ConditionWatch, name.to_s, name: name, run: events, to_s: name.to_s, clear_history!: nil, :logger= => nil)
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
  def recorded_events
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

  describe '#initialize' do
    describe 'defaults' do
      [
        :start_command, :stop_command, :restart_command, :stdout, :stderr, :stdin,
        :daemonize, :pid_file, :working_dir, :uid, :gid, :child_process_factory,
        :pid_command, :auto_start, :supplementary_groups, :stop_signals,
        :post_start_command, :pre_stop_command, :post_stop_command, :notify_command,
        :app_name, :group_name
      ].each do |attr|
        describe "##{attr}" do
          subject { super().send(attr) }

          it { is_expected.to be_nil }
        end
      end

      describe '#monitor_children' do
        subject { super().monitor_children }

        it { is_expected.to be false }
      end

      describe '#hook_timeout' do
        subject { super().hook_timeout }

        it { is_expected.to eq 30 }
      end

      describe '#cache_actual_pid' do
        subject { super().cache_actual_pid }

        it { is_expected.to be true }
      end

      describe '#start_grace_time' do
        subject { super().start_grace_time }

        it { is_expected.to eq 3 }
      end

      describe '#stop_grace_time' do
        subject { super().stop_grace_time }

        it { is_expected.to eq 3 }
      end

      describe '#restart_grace_time' do
        subject { super().restart_grace_time }

        it { is_expected.to eq 3 }
      end

      describe '#on_start_timeout' do
        subject { super().on_start_timeout }

        it { is_expected.to eq 'start' }
      end

      describe '#environment' do
        subject { super().environment }

        it { is_expected.to eq({}) }
      end

      describe '#state' do
        subject { super().state }

        it { is_expected.to eq 'unmonitored' }
      end

      [:group_start_noblock, :group_stop_noblock, :group_restart_noblock, :group_unmonitor_noblock].each do |attr|
        describe "##{attr}" do
          subject { super().send(attr) }

          it { is_expected.to be true }
        end
      end
    end

    it 'works without options' do
      process = described_class.new(:proc_name, [])
      expect(process.name).to eq :proc_name
      expect(process.children).to eq []
      expect(process.statistics).to be_a(Bluepill::ProcessStatistics)
      expect(process.statistics.events.size).to eq 0
      expect(process.instance_variable_get(:@threads)).to eq []
      expect(process.instance_variable_get(:@event_mutex)).to be_a(Monitor)
    end

    describe 'overrides' do
      subject(:process) { described_class.new(:proc_name, [], start_grace_time: 17) }

      describe '#start_grace_time' do
        subject { super().start_grace_time }

        it { is_expected.to eq 17 }
      end
    end

    context 'with checks' do
      subject(:process) do
        described_class.new(:proc_name, {flapping: {times: 2}, mem_usage: {below: 100, every: 10}}, logger: logger)
      end

      it 'adds triggers and watches' do
        expect(process.triggers.size).to eq 1
        expect(process.triggers.first).to be_a(Bluepill::Triggers::Flapping)
        expect(process.triggers.first.logger).to eq logger
        expect(process.triggers.first.times).to eq 2
        expect(process.triggers.first.process).to be process
        expect(process.watches.size).to eq 1
        expect(process.watches.first.name).to eq :mem_usage
        expect(process.watches.first.logger).to eq logger
        expect(process.watches.first.instance_variable_get(:@every)).to eq 10
      end

      it 'propagates a new logger to watches and triggers' do
        new_logger = instance_double(Bluepill::Logger).as_null_object
        process.logger = new_logger
        expect(process.logger).to eq new_logger
        expect(process.watches.first.logger).to eq new_logger
        expect(process.triggers.first.logger).to eq new_logger
      end
    end

    it 'accepts an actual pid' do
      process = described_class.new(:proc_name, [], logger: logger, actual_pid: 42)
      expect(process.actual_pid).to eq 42
    end
  end

  describe '#tick' do
    it 'does nothing while skipping ticks' do
      process.skip_ticks_until = now.to_i + 10
      thread = leftover_thread
      process.tick
      expect(thread).not_to have_received(:kill)
      expect(process.skip_ticks_until).to eq now.to_i + 10
    end

    it 'rechecks whether the process is running on every tick' do
      watch = watch_double(:w, [])
      process.watches << watch
      process.state = 'up'
      run_process
      process.process_running = true
      allow(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH)
      process.tick
      expect(watch).not_to have_received(:run)
      expect(process).to be_down
    end

    it 'cleans threads when unmonitored and stays unmonitored' do
      process.skip_ticks_until = now.to_i - 1
      thread = leftover_thread
      process.tick
      expect(thread).to have_received(:kill)
      expect(process.skip_ticks_until).to be_nil
      expect(process).to be_unmonitored
    end

    it 'leaves threads alone when the process is monitored' do
      process.state = 'up'
      run_process
      thread = leftover_thread
      process.tick
      expect(thread).not_to have_received(:kill)
    end

    it 'transitions from down to starting when not running' do
      watch = watch_double(:w, [])
      process.watches << watch
      process.state = 'down'
      process.start_command = 'start-cmd'
      process.tick
      expect(Bluepill::System).to have_received(:execute_blocking).with('start-cmd', anything)
      expect(watch).not_to have_received(:run)
      expect(process).to be_starting
    end

    it 'transitions from down to up when running, and runs watches' do
      watch = watch_double(:w, [])
      process.watches << watch
      process.state = 'down'
      run_process
      allow(Bluepill::System).to receive(:get_children)
      process.tick
      expect(watch).to have_received(:run)
      expect(Bluepill::System).not_to have_received(:get_children)
      expect(process).to be_up
    end

    it 'ticks children when monitoring children' do
      child = instance_double(Bluepill::Process, 'child', process_running?: true, actual_pid: 7, tick: nil)
      process.state = 'up'
      process.monitor_children = true
      run_process
      process.children << child
      allow(Bluepill::System).to receive(:get_children).with(5).and_return([7])
      process.tick
      expect(child).to have_received(:tick)
      expect(process).to be_up
    end

    {
      'starting' => %w[up down],
      'up' => %w[up down],
      'stopping' => %w[up down],
      'restarting' => %w[up down],
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

  describe 'events' do
    it 'starts the process on start' do
      process.start_command = 'start-cmd'
      process.dispatch!(:start, 'reason')
      expect(Bluepill::System).to have_received(:execute_blocking).with('start-cmd', anything)
      expect(process).to be_starting
      expect(process.statistics.events.first[0, 2]).to eq [:start, 'reason']
    end

    it 'handles one event at a time' do
      expect(process.instance_variable_get(:@event_mutex)).to receive(:synchronize).and_call_original
      process.dispatch!('start')
      expect(process).to be_starting
    end

    it 'stops the process on stop' do
      process.state = 'up'
      run_process
      process.dispatch!(:stop)
      expect(::Process).to have_received(:kill).with('TERM', 5)
      expect(process).to be_stopping
    end

    it 'restarts the process on restart' do
      process.state = 'down'
      process.restart_command = 'restart-cmd'
      process.dispatch!(:restart)
      expect(Bluepill::System).to have_received(:execute_blocking).with('restart-cmd', anything)
      expect(process).to be_restarting
    end

    it 'cleans threads when leaving stopping' do
      process.state = 'stopping'
      thread = leftover_thread
      process.dispatch!(:unmonitor)
      expect(thread).to have_received(:kill)
      expect(process).to be_unmonitored
    end
  end

  describe '#record_transition' do
    it 'ignores loopback transitions' do
      transition = Bluepill::Process::Transition.new(:up, :up)
      expect(logger).not_to receive(:info)
      process.record_transition(transition)
      expect(process.instance_variable_get(:@transitioned)).to be_nil
    end

    it 'clears watch history and logs' do
      watch = watch_double(:w, [])
      process.watches << watch
      transition = Bluepill::Process::Transition.new(:up, :down)
      expect(watch).to receive(:clear_history!)
      expect(logger).to receive(:info).with('Going from up => down')
      expect(logger).not_to receive(:warning)
      process.record_transition(transition)
      expect(process.instance_variable_get(:@transitioned)).to be true
    end

    it 'clears the child list when monitoring children' do
      process.monitor_children = true
      process.children << instance_double(Bluepill::Process, 'child')
      transition = Bluepill::Process::Transition.new(:up, :down)
      expect(logger).to receive(:warning).with('Clearing child list')
      process.record_transition(transition)
      expect(process.children).to be_empty
    end
  end

  describe '#notify_triggers' do
    let(:transition) { Bluepill::Process::Transition.new(:up, :down) }
    let(:trigger) { instance_double(Bluepill::Trigger, 'trigger', :logger= => nil) }

    before { process.triggers << trigger }

    it 'notifies each trigger' do
      expect(trigger).to receive(:notify).with(transition)
      process.notify_triggers(transition)
    end

    it 'logs and re-raises errors' do
      error = RuntimeError.new('boom')
      error.set_backtrace(%w[a b])
      allow(trigger).to receive(:notify).and_raise(error)
      expect(logger).to receive(:err).with(%w[a b])
      expect { process.notify_triggers(transition) }.to raise_error(error)
    end
  end

  describe '#add_watch' do
    it 'adds a condition watch' do
      process.add_watch(:mem_usage, below: 10)
      expect(process.watches.first).to be_a(Bluepill::ConditionWatch)
      expect(process.watches.first.logger).to eq logger
    end
  end

  describe '#run_watches' do
    before { process.actual_pid = 5 }

    it 'dispatches events from watches' do
      quiet = watch_double(:quiet, [])
      loud = watch_double(:loud, [:restart, :stop])
      allow(loud).to receive(:to_s).and_return('loud: [1, 2]')
      process.watches << quiet << loud
      expect(logger).to receive(:info).once.with('loud dispatched: restart,stop')
      expect(logger).not_to receive(:info).with('quiet dispatched: ')
      process.run_watches
      expect(quiet).to have_received(:run).with(5, now.to_i)
      expect(recorded_events).to eq [[:restart, 'loud: [1, 2]'], [:stop, 'loud: [1, 2]']]
    end

    it 'dispatches after a transition in an earlier run' do
      process.instance_variable_set(:@transitioned, true)
      process.watches << watch_double(:loud, [:restart])
      process.run_watches
      expect(recorded_events).to eq [[:restart, 'loud']]
    end

    it 'stops dispatching after a transition' do
      process.state = 'down'
      process.watches << watch_double(:loud, [:start, :stop])
      process.run_watches
      expect(recorded_events).to eq [[:start, 'loud']]
    end
  end

  describe '#determine_initial_state' do
    it 'is up when running' do
      run_process
      process.determine_initial_state
      expect(process.state).to eq 'up'
    end

    it 'checks again, even if the process was running earlier in the tick' do
      process.process_running = true
      process.determine_initial_state
      expect(process.state).to eq 'down'
    end

    it 'is unmonitored when auto_start is false' do
      process.auto_start = false
      process.determine_initial_state
      expect(process.state).to eq 'unmonitored'
    end

    it 'is down otherwise' do
      process.determine_initial_state
      expect(process.state).to eq 'down'
    end
  end

  describe '#handle_user_command' do
    it 'refuses to start a running process' do
      run_process
      expect(logger).to receive(:warning).with('Refusing to re-run start command on an already running process.')
      process.handle_user_command('start')
      expect(recorded_events).to be_empty
    end

    it 'starts a stopped process' do
      process.handle_user_command('start')
      expect(recorded_events).to eq [[:start, 'user initiated']]
    end

    it 'checks again before starting, even if the process was running earlier in the tick' do
      process.process_running = true
      process.handle_user_command('start')
      expect(recorded_events).to eq [[:start, 'user initiated']]
    end

    it 'stops and unmonitors' do
      process.state = 'up'
      run_process
      process.handle_user_command('stop')
      expect(::Process).to have_received(:kill).with('TERM', 5)
      expect(recorded_events).to eq [[:unmonitor, 'user initiated']]
    end

    it 'restarts through the state machine' do
      process.state = 'up'
      process.restart_command = 'restart-cmd'
      process.handle_user_command('restart')
      expect(recorded_events).to eq [[:restart, 'user initiated']]
      expect(Bluepill::System).to have_received(:execute_blocking).with('restart-cmd', anything).once
    end

    it 'restarts an up process by going to restarting' do
      process.state = 'up'
      process.handle_user_command('restart')
      expect(process.state).to eq('restarting')
    end

    it 'restarts directly from a state restart cannot leave' do
      process.state = 'unmonitored'
      process.restart_command = 'restart-cmd'
      process.handle_user_command('restart')
      expect(Bluepill::System).to have_received(:execute_blocking).with('restart-cmd', anything).once
      expect(process.state).to eq('unmonitored')
    end

    it 'resets triggers and unmonitors' do
      trigger = instance_double(Bluepill::Trigger, 'trigger', :logger= => nil, notify: nil)
      process.triggers << trigger
      expect(trigger).to receive(:reset!)
      process.handle_user_command('unmonitor')
      expect(recorded_events).to eq [[:unmonitor, 'user initiated']]
    end

    it 'ignores unknown commands' do
      expect(process.handle_user_command('bogus')).to be_nil
      expect(recorded_events).to be_empty
    end
  end

  describe 'predicates' do
    it 'are false, not nil, for unset attributes' do
      process.cache_actual_pid = nil
      process.monitor_children = nil
      expect(process.cache_actual_pid?).to be false
      expect(process.monitor_children?).to be false
      expect(process.daemonize?).to be false
    end

    it 'are true, not the attribute, for set attributes' do
      process.cache_actual_pid = 1
      process.monitor_children = 1
      process.daemonize = 1
      expect(process.cache_actual_pid?).to be true
      expect(process.monitor_children?).to be true
      expect(process.daemonize?).to be true
    end
  end

  describe '#process_running?' do
    before { process.actual_pid = 5 }

    it 'memoizes a running result' do
      expect(process.process_running?).to be true
      expect(process.process_running?).to be true
      expect(::Process).to have_received(:kill).once.with(0, 5)
      expect(process.actual_pid).to eq 5
    end

    it 'rechecks when forced' do
      process.process_running?
      process.process_running?(true)
      expect(::Process).to have_received(:kill).twice.with(0, 5)
    end

    it 'clears the pid when not running' do
      allow(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH)
      expect(process.process_running?).to be false
      expect(process.instance_variable_get(:@actual_pid)).to be_nil
    end
  end

  describe '#start_process' do
    before { process.start_command = '/etc/init.d/script start' }

    it 'functions' do
      allow(Timeout).to receive(:timeout).and_call_original
      expect(logger).to receive(:warning).with('Executing start command: /etc/init.d/script start')
      process.start_process
      expect(Bluepill::System).to have_received(:execute_blocking).with('/etc/init.d/script start', process.system_command_options)
      expect(Timeout).to have_received(:timeout).with(3)
      expect(process.skip_ticks_until).to eq now.to_i + 3
    end

    it 'dispatches on_start_timeout when the start command takes too long' do
      process.on_start_timeout = 'unmonitor'
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.start_process
      expect(recorded_events).to eq [['unmonitor', nil]]
    end

    it 'runs the pre start command first' do
      process.pre_start_command = 'prepare'
      expect(Bluepill::System).to receive(:execute_blocking).
        with('prepare', anything).ordered.
        and_return(exit_code: 0)
      expect(Bluepill::System).to receive(:execute_blocking).
        with('/etc/init.d/script start', anything).ordered.
        and_return(exit_code: 0)
      process.start_process
    end

    it 'warns on a non-zero exit code' do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      expect(logger).to receive(:warning).with('Start command execution returned non-zero exit code:')
      expect(logger).to receive(:warning).with({exit_code: 1}.inspect)
      process.start_process
    end

    it 'warns when a signal killed the command' do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: nil)
      expect(logger).to receive(:warning).with('Start command execution returned non-zero exit code:')
      expect(logger).to receive(:warning).with({exit_code: nil}.inspect)
      process.start_process
    end

    it 'kills a stop signal thread left from an earlier stop' do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 0)
      stop_thread = Thread.new { sleep }
      process.instance_variable_get(:@threads) << stop_thread
      process.start_process
      stop_thread.join(1)
      expect(stop_thread).not_to be_alive
      expect(process.instance_variable_get(:@threads)).to be_empty
    end

    context 'when daemonizing' do
      before { process.daemonize = true }

      it 'journals the daemon pid' do
        allow(Bluepill::System).to receive(:daemonize).and_return(99)
        expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).with(:proc_name)
        expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 99)
        process.start_process
        expect(Bluepill::System).to have_received(:daemonize).with('/etc/init.d/script start', process.system_command_options)
      end

      it 'journals children pids when monitoring children' do
        process.monitor_children = true
        process.children << instance_double(Bluepill::Process, 'child', actual_pid: 100)
        allow(Bluepill::System).to receive(:daemonize).and_return(99)
        expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 99)
        expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 100)
        process.start_process
      end

      it 'does not journal when daemonizing fails' do
        allow(Bluepill::System).to receive(:daemonize).and_return(nil)
        expect(Bluepill::ProcessJournal).not_to receive(:append_pid_to_journal)
        process.start_process
      end
    end
  end

  describe '#pre_start_process' do
    it 'does nothing without a pre start command' do
      expect(Bluepill::System).not_to receive(:execute_blocking)
      process.pre_start_process
    end

    context 'with a pre start command' do
      before { process.pre_start_command = 'prepare' }

      it 'executes it' do
        expect(logger).to receive(:warning).once.with('Executing pre start command: prepare')
        expect(logger).not_to receive(:warning).with('Pre start command execution returned non-zero exit code:')
        process.pre_start_process
        expect(Bluepill::System).to have_received(:execute_blocking).with('prepare', process.system_command_options)
      end

      it 'warns on a non-zero exit code' do
        allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 2)
        expect(logger).to receive(:warning).with('Pre start command execution returned non-zero exit code:')
        process.pre_start_process
      end
    end
  end

  describe '#stop_process' do
    before { process.actual_pid = 5 }

    it 'functions' do
      process.stop_command = '/etc/init.d/script stop'
      allow(Timeout).to receive(:timeout).and_call_original
      process.stop_process
      expect(Bluepill::System).to have_received(:execute_blocking).with('/etc/init.d/script stop', process.system_command_options)
      expect(Timeout).to have_received(:timeout).with(3)
    end

    it 'dispatches stop when the stop command takes too long' do
      process.stop_command = '/etc/init.d/script stop'
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.stop_process
      expect(recorded_events).to eq [['stop', nil]]
    end

    it 'substitutes the pid and warns on a non-zero exit code' do
      process.stop_command = 'kill {{PID}}; wait {{PID}}'
      process.pid_file = 'some.pid'
      expect(Bluepill::System).not_to receive(:get_children)
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      expect(logger).to receive(:warning).with('Executing stop command: kill 5; wait 5').ordered
      expect(logger).to receive(:warning).with('Stop command execution returned non-zero exit code:').ordered
      expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).with(:proc_name)
      expect(Bluepill::System).to receive(:delete_if_exists).with('some.pid')
      process.stop_process
      expect(Bluepill::System).to have_received(:execute_blocking).with('kill 5; wait 5', anything)
    end

    it 'journals children when monitoring children' do
      process.monitor_children = true
      allow(Bluepill::System).to receive(:get_children).with(5).and_return([6, 7])
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 6)
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 7)
      process.stop_process
    end

    it 'journals no children when stopped before it has a pid' do
      process.clear_pid
      process.monitor_children = true
      allow(Bluepill::System).to receive(:ps_axu).and_return(0 => %w[PID PPID %CPU RSS ELAPSED COMMAND])
      allow(Bluepill::System).to receive(:delete_if_exists)
      expect(Bluepill::ProcessJournal).not_to receive(:append_pid_to_journal)
      process.stop_process
    end

    it 'sends TERM by default' do
      expect(logger).to receive(:warning).with('Executing default stop command. Sending TERM signal to 5')
      expect(::Process).to receive(:kill).with('TERM', 5)
      expect(Bluepill::System).to receive(:delete_if_exists).with(nil)
      process.stop_process
      expect(process.skip_ticks_until).to eq now.to_i + 3
    end

    context 'with stop signals' do
      # The seconds the process sleeps for. Kernel#sleep is the one method of
      # the process stubbed, since nothing else can stand in for the clock.
      let(:sleeps) { [] }

      before { allow(process).to receive(:sleep) { |seconds| sleeps << seconds } }

      def run_stop_signals
        process.stop_process
        process.instance_variable_get(:@threads).each(&:join)
      end

      it 'sends a single signal' do
        process.stop_signals = [:quit]
        expect(logger).to receive(:warning).with('Sending stop signals to 5')
        expect(logger).to receive(:info).with('Sending signal quit to 5')
        expect(::Process).to receive(:kill).with('QUIT', 5)
        expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).with(:proc_name)
        run_stop_signals
      end

      it 'sends each signal with a delay while the process is alive' do
        process.stop_signals = [:quit, 2, :term, 3, :kill]
        expect(logger).to receive(:info).with('Sending signal quit to 5')
        expect(logger).to receive(:debug).with('Sleeping for 2 seconds')
        expect(logger).to receive(:info).with('Sending signal term to 5')
        expect(logger).to receive(:debug).with('Sleeping for 3 seconds')
        expect(logger).to receive(:info).with('Sending signal kill to 5')
        expect(::Process).to receive(:kill).with('QUIT', 5).ordered
        expect(::Process).to receive(:kill).with(0, 5).ordered
        expect(::Process).to receive(:kill).with('TERM', 5).ordered
        expect(::Process).to receive(:kill).with(0, 5).ordered
        expect(::Process).to receive(:kill).with('KILL', 5).ordered
        run_stop_signals
        expect(sleeps).to eq [2, 3]
        expect(process.stop_signals).to eq [:quit, 2, :term, 3, :kill]
      end

      it 'stops once the process has terminated' do
        process.stop_signals = [:quit, 2, :kill]
        allow(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH)
        expect(::Process).to receive(:kill).with('QUIT', 5)
        expect(::Process).not_to receive(:kill).with('KILL', 5)
        expect(logger).to receive(:debug).with('Process has terminated.')
        expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).once
        run_stop_signals
      end

      it 'rounds a fractional wait up to whole seconds' do
        process.stop_signals = [:quit]
        process.stop_grace_time = 4.5
        expect(::Process).to receive(:kill).with(0, 5).exactly(3).times
        run_stop_signals
        expect(sleeps).to eq [1, 1, 1]
      end

      it 'waits for the process to exit before cleaning up' do
        process.stop_signals = [:quit]
        process.stop_grace_time = 5
        expect(::Process).to receive(:kill).with('QUIT', 5).ordered
        expect(::Process).to receive(:kill).with(0, 5).exactly(3).times.ordered
        expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).ordered
        run_stop_signals
        expect(sleeps).to eq [1, 1, 1]
      end

      it 'cleans up as soon as the process exits after the last signal' do
        process.stop_signals = [:quit, 2, :term]
        process.stop_grace_time = 10
        alive = [1, 1]
        allow(::Process).to receive(:kill).with(0, 5) { alive.shift || raise(Errno::ESRCH) }
        expect(::Process).to receive(:kill).with('TERM', 5)
        expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal)
        run_stop_signals
        expect(sleeps).to eq [2, 1]
      end
    end
  end

  describe '#restart_process' do
    it 'functions' do
      process.restart_command = '/etc/init.d/script restart'
      allow(Timeout).to receive(:timeout).and_call_original
      process.restart_process
      expect(Bluepill::System).to have_received(:execute_blocking).with('/etc/init.d/script restart', process.system_command_options)
      expect(Timeout).to have_received(:timeout).with(3)
      expect(process.skip_ticks_until).to eq now.to_i + 3
    end

    it 'dispatches restart when the restart command takes too long' do
      process.restart_command = '/etc/init.d/script restart'
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.restart_process
      expect(recorded_events).to eq [['restart', nil]]
    end

    it 'substitutes the pid and warns on a non-zero exit code' do
      process.restart_command = 'restart {{PID}}'
      process.actual_pid = 5
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      expect(logger).to receive(:warning).with('Executing restart command: restart 5').ordered
      expect(logger).to receive(:warning).with('Restart command execution returned non-zero exit code:').ordered
      process.restart_process
      expect(Bluepill::System).to have_received(:execute_blocking).with('restart 5', anything)
    end

    it 'stops and starts without a restart command' do
      run_process
      process.start_command = 'start-cmd'
      events = []
      allow(::Process).to receive(:kill) { |signal, _pid| events << signal }
      allow(Bluepill::System).to receive(:execute_blocking) { |command, _options| events << command && {exit_code: 0} }
      expect(logger).to receive(:warning).with('No restart_command specified. Must stop and start to restart')
      process.restart_process
      expect(events).to eq ['TERM', 'start-cmd']
    end

    it 'waits for the stop signals to finish before starting' do
      run_process
      process.start_command = 'start-cmd'
      # A real delay, and a grace time that leaves nothing to wait for after
      # the last signal
      process.stop_signals = [:quit, 0.1, :kill]
      process.stop_grace_time = 2
      events = []
      allow(::Process).to receive(:kill) { |signal, _pid| events << signal }
      allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal) { events << :cleanup }
      allow(Bluepill::System).to receive(:execute_blocking) { |command, _options| events << command && {exit_code: 0} }
      process.restart_process
      expect(events).to eq ['QUIT', 0, 'KILL', :cleanup, :cleanup, 'start-cmd']
    end
  end

  describe '#clean_threads' do
    it 'kills and clears threads' do
      thread = instance_double(Thread, 'thread')
      process.instance_variable_get(:@threads) << thread
      expect(thread).to receive(:kill)
      process.clean_threads
      expect(process.instance_variable_get(:@threads)).to be_empty
    end
  end

  describe '#signal_process' do
    before { process.actual_pid = 5 }

    it 'upcases string signals' do
      expect(::Process).to receive(:kill).with('HUP', 5)
      expect(process.signal_process('hup')).to be true
    end

    it 'upcases strings of a String subclass' do
      expect(::Process).to receive(:kill).with('HUP', 5)
      expect(process.signal_process(Class.new(String).new('hup'))).to be true
    end

    it 'turns symbol signals into upcased strings' do
      expect(::Process).to receive(:kill).with('HUP', 5)
      expect(process.signal_process(:hup)).to be true
    end

    it 'signals pid 1' do
      process.actual_pid = 1
      expect(::Process).to receive(:kill).with(0, 1)
      expect(process.signal_process(0)).to be true
    end

    it 'passes integer signals through' do
      expect(::Process).to receive(:kill).with(9, 5)
      expect(process.signal_process(9)).to be true
    end

    it 'logs and returns false on failure' do
      allow(::Process).to receive(:kill).and_raise(Errno::EPERM)
      expect(logger).to receive(:err).with(/Failed to signal process 5 with code 0/)
      expect(process.signal_process(0)).to be false
    end

    it 'never signals a pid of 0 or less' do
      [0, -1].each do |pid|
        process.instance_variable_set(:@actual_pid, pid)
        expect(logger).to receive(:err).with("Failed to signal process #{pid} with code 0: invalid pid #{pid}")
        expect(process.signal_process(0)).to be false
      end
      expect(::Process).not_to have_received(:kill)
    end

    it 'returns false without an error when there is no pid' do
      process.instance_variable_set(:@actual_pid, nil)
      allow(logger).to receive(:err)
      expect(process.signal_process(0)).to be false
      expect(logger).not_to have_received(:err)
      expect(::Process).not_to have_received(:kill)
    end
  end

  describe '#actual_pid' do
    it 'uses the pid command when configured' do
      process.pid_command = 'echo 123'
      expect(process.actual_pid).to eq 123
    end

    it 'returns nil when the pid command prints 0' do
      process.pid_command = 'echo 0'
      expect(process.actual_pid).to be_nil
    end

    it 'returns nil when the pid command output is not a number' do
      process.pid_command = 'echo oops'
      expect(process.actual_pid).to be_nil
    end

    it 'returns nil when the pid command output only starts with a number' do
      process.pid_command = 'echo 12 oops'
      expect(process.actual_pid).to be_nil
    end

    it 'ignores whitespace and leading zeros around the pid command output' do
      process.pid_command = "echo '  0123'"
      expect(process.actual_pid).to eq 123
    end

    it 'is nil without a pid file' do
      expect(process.actual_pid).to be_nil
    end

    context 'with a pid file' do
      let(:dir) { Dir.mktmpdir }

      before { process.pid_file = File.join(dir, 'proc.pid') }

      after { FileUtils.remove_entry(dir) }

      it 'reads the pid and caches it' do
        File.write(process.pid_file, "77\n")
        expect(process.actual_pid).to eq 77
        File.write(process.pid_file, "78\n")
        expect(process.actual_pid).to eq 77
      end

      it 'forgets the cached pid when it cleans up after a stop' do
        allow(Bluepill::System).to receive(:delete_if_exists).and_call_original
        File.write(process.pid_file, "77\n")
        expect(process.actual_pid).to eq 77
        process.cleanup_process
        expect(File.exist?(process.pid_file)).to be false
        File.write(process.pid_file, "78\n")
        expect(process.actual_pid).to eq 78
      end

      it 'rereads the pid when not caching' do
        process.cache_actual_pid = false
        File.write(process.pid_file, "77\n")
        expect(process.actual_pid).to eq 77
        File.write(process.pid_file, "78\n")
        expect(process.actual_pid).to eq 78
      end

      it 'is nil for an empty pid file' do
        File.write(process.pid_file, '')
        expect(process.actual_pid).to be_nil
      end

      it 'is nil for a pid file that does not hold a positive pid' do
        process.cache_actual_pid = false
        ["0\n", "\n", 'garbage', '-5'].each do |content|
          File.write(process.pid_file, content)
          expect(process.actual_pid).to be_nil
        end
      end

      it 'is not running for a pid file that holds 0' do
        File.write(process.pid_file, "0\n")
        allow(::Process).to receive(:kill).and_call_original
        expect(process.process_running?(true)).to be false
      end

      it 'reads pid 1' do
        File.write(process.pid_file, "1\n")
        expect(process.actual_pid).to eq 1
      end

      it 'warns when the pid file does not exist' do
        expect(logger).to receive(:warning).with("pid_file #{process.pid_file} does not exist or cannot be read")
        expect(process.actual_pid).to be_nil
      end
    end
  end

  describe '#actual_pid=' do
    it 'journals the pid' do
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 12)
      process.actual_pid = 12
      expect(process.actual_pid).to eq 12
    end
  end

  describe '#skip_ticks_for' do
    it 'adds to an existing skip' do
      process.skip_ticks_until = now.to_i + 5
      process.skip_ticks_for(2.5)
      expect(process.skip_ticks_until).to eq now.to_i + 7
    end

    it 'starts from now without a skip' do
      process.skip_ticks_for(2)
      expect(process.skip_ticks_until).to eq now.to_i + 2
    end
  end

  describe '#refresh_children!' do
    let(:factory) { instance_double(Bluepill::ProcessFactory, 'factory') }
    let(:child_logger) { instance_double(Bluepill::Logger, 'child logger') }

    before do
      process.actual_pid = 5
      process.child_process_factory = factory
      allow(logger).to receive(:prefix_with).and_return(child_logger)
    end

    it 'prunes dead children and adds new ones' do
      dead = instance_double(Bluepill::Process, 'dead', actual_pid: 6)
      alive = instance_double(Bluepill::Process, 'alive', actual_pid: 7)
      other = instance_double(Bluepill::Process, 'other', actual_pid: 9, process_running?: true)
      new_child = instance_double(Bluepill::Process, 'new child')
      process.children << dead << alive << other
      allow(dead).to receive(:process_running?).with(true).and_return(false)
      allow(alive).to receive(:process_running?).with(true).and_return(true)
      allow(Bluepill::System).to receive(:get_children).with(5).and_return([7, 8, 9])
      expect(logger).to receive(:info).with('Existing children: 7,9. Got new children: [8] for 5')
      expect(logger).to receive(:prefix_with).with('<child(pid:8)>')
      allow(factory).to receive(:create_child_process).
        with('<child(pid:8)>', 8, child_logger).
        and_return(new_child)
      expect(Bluepill::ProcessJournal).not_to receive(:append_pid_to_journal)
      process.refresh_children!
      expect(process.children).to eq [alive, other, new_child]
    end

    it 'journals new children when daemonized' do
      process.daemonize = true
      allow(Bluepill::System).to receive(:get_children).and_return([8])
      allow(factory).to receive(:create_child_process).and_return(instance_double(Bluepill::Process, 'child'))
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 8)
      process.refresh_children!
    end

    it 'does nothing without new children' do
      allow(Bluepill::System).to receive(:get_children).and_return([])
      expect(logger).not_to receive(:info)
      process.refresh_children!
      expect(process.children).to be_empty
    end
  end

  describe '#with_timeout' do
    let(:block) { proc {} }

    it 'returns the result of the block' do
      expect(process.with_timeout(3, 'state_override') { :done }).to eq :done
    end

    it 'proceeds to next_state on timeout.' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      expect(logger).to receive(:err).with('Execution is taking longer than expected.').ordered
      expect(logger).to receive(:err).with('Did you forget to tell bluepill to daemonize this process?').ordered
      process.with_timeout(3, 'unmonitor', &block)
      expect(Timeout).to have_received(:timeout).with(3)
      expect(recorded_events).to eq [['unmonitor', nil]]
    end

    it 'times out after a fraction of a second' do
      process.with_timeout(0.01, 'unmonitor') { Kernel.sleep 1 }
      expect(recorded_events).to eq [['unmonitor', nil]]
    end
  end

  describe '#system_command_options' do
    it 'passes the process settings to the command' do
      process.uid = 'user'
      process.gid = 'group'
      process.working_dir = '/work'
      process.environment = {'A' => 'b'}
      process.pid_file = 'proc.pid'
      process.stdin = 'in'
      process.stdout = 'out'
      process.stderr = 'err'
      process.supplementary_groups = ['extra']
      expect(process.system_command_options).to eq(
        uid: 'user',
        gid: 'group',
        working_dir: '/work',
        environment: {'A' => 'b'},
        pid_file: 'proc.pid',
        logger: logger,
        stdin: 'in',
        stdout: 'out',
        stderr: 'err',
        supplementary_groups: ['extra']
      )
    end
  end

  describe '#clear_pid' do
    it 'keeps the last pid for notify_command' do
      process.actual_pid = 5
      process.clear_pid
      process.clear_pid
      expect(process.instance_variable_get(:@actual_pid)).to be_nil
      expect(process.instance_variable_get(:@last_pid)).to eq 5
    end
  end

  describe '#run_hook' do
    let(:options) { process.system_command_options }

    it "runs the command with the pid, and the process's options and environment" do
      process.environment = {'A' => '1'}
      expect(logger).to receive(:info).with('Executing post start command: renice 20 7 7')
      expect(logger).not_to receive(:warning)
      process.run_hook('renice 20 {{PID}} {{PID}}', 'Post start', 7, 'B' => '2')
      expect(Bluepill::System).to have_received(:execute_blocking).
        with('renice 20 7 7', options.merge(environment: {'A' => '1', 'B' => '2'}, timeout: 30))
    end

    it 'adds nothing to the environment by default' do
      process.run_hook('drain', 'Pre stop', 7)
      expect(Bluepill::System).to have_received(:execute_blocking).with('drain', options.merge(timeout: 30))
    end

    it 'runs without an environment of its own' do
      process.environment = nil
      process.run_hook('alert', 'Notify', nil, 'B' => '2')
      expect(Bluepill::System).to have_received(:execute_blocking).with('alert', hash_including(environment: {'B' => '2'}))
    end

    it 'logs a non-zero exit code' do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      expect(logger).to receive(:warning).with('Notify command execution returned non-zero exit code:')
      process.run_hook('alert', 'Notify', 7)
    end

    it 'gives the command hook_timeout, and logs one that runs longer' do
      process.hook_timeout = 5
      allow(Bluepill::System).to receive(:execute_blocking).with('drain 7', hash_including(timeout: 5)).and_raise(Timeout::Error)
      expect(logger).to receive(:warning).with('Pre stop command took longer than 5 seconds: drain {{PID}}')
      process.run_hook('drain {{PID}}', 'Pre stop', 7)
    end

    it 'logs a command that fails to run, without raising' do
      allow(Bluepill::System).to receive(:execute_blocking).and_raise(Errno::EAGAIN, 'fork')
      expect(logger).to receive(:err).with('Post stop command failed: Resource temporarily unavailable - fork')
      expect { process.run_hook('cleanup', 'Post stop', 7) }.not_to raise_error
    end
  end

  describe '#run_hook_in_background' do
    it 'runs the hook in a thread of its own' do
      ran_on = []
      allow(Bluepill::System).to receive(:execute_blocking) { ran_on << Thread.current && {exit_code: 0} }
      thread = process.run_hook_in_background('alert', 'Notify', 5, 'A' => '1')
      thread.join
      expect(ran_on).to eq [thread]
    end

    it 'runs the hook with its description, pid and environment' do
      process.run_hook_in_background('alert {{PID}}', 'Notify', 5, 'A' => '1').join
      expect(Bluepill::System).to have_received(:execute_blocking).with('alert 5', hash_including(environment: {'A' => '1'}))
      expect(logger).to have_received(:info).with('Executing notify command: alert 5')
    end

    it 'adds nothing to the environment by default' do
      process.environment = {'A' => '1'}
      process.run_hook_in_background('renice', 'Post start', 5).join
      expect(Bluepill::System).to have_received(:execute_blocking).with('renice', hash_including(environment: {'A' => '1'}))
    end
  end

  describe '#post_start_process' do
    it 'does nothing without a post start command' do
      expect(process.post_start_process).to be_nil
    end

    it 'runs the post start command with the pid in the background' do
      run_process
      process.post_start_command = 'renice 20 {{PID}}'
      process.post_start_process.join
      expect(Bluepill::System).to have_received(:execute_blocking).with('renice 20 5', anything)
      expect(logger).to have_received(:info).with('Executing post start command: renice 20 5')
    end

    %w[starting restarting].each do |state|
      it "runs when the process comes up from #{state}" do
        threads = capture_threads
        process.post_start_command = 'renice'
        process.state = state
        run_process
        process.tick
        threads.each(&:join)
        expect(Bluepill::System).to have_received(:execute_blocking).with('renice', anything)
        expect(process).to be_up
      end
    end

    %w[down up stopping].each do |state|
      it "doesn't run when a process comes back up by itself, or stays up, from #{state}" do
        threads = capture_threads
        process.post_start_command = 'renice'
        process.state = state
        run_process
        process.tick
        expect(threads).to be_empty
      end
    end
  end

  describe '#pre_stop_process' do
    before { run_process }

    it 'runs the pre stop command, and waits for it, before stopping' do
      process.pre_stop_command = 'drain {{PID}}'
      events = []
      allow(Bluepill::System).to receive(:execute_blocking) { |command, _options| events << command && {exit_code: 0} }
      allow(::Process).to receive(:kill) { |signal, _pid| events << signal }
      process.stop_process
      expect(events).to eq ['drain 5', 'TERM']
    end

    it 'runs the pre stop command as Pre stop' do
      process.pre_stop_command = 'drain {{PID}}'
      process.stop_process
      expect(logger).to have_received(:info).with('Executing pre stop command: drain 5')
    end

    it 'does nothing without a pre stop command' do
      process.stop_process
      expect(Bluepill::System).not_to have_received(:execute_blocking)
    end
  end

  describe '#post_stop_process' do
    before { run_process }

    it 'runs the post stop command in the background, after cleaning up' do
      threads = capture_threads
      process.post_stop_command = 'rm /tmp/{{PID}}.sock'
      events = []
      allow(Bluepill::System).to receive(:delete_if_exists) { events << :unlink }
      allow(Bluepill::System).to receive(:execute_blocking) { |command, _options| events << [command, Thread.current] && {exit_code: 0} }
      process.stop_process
      threads.each(&:join)
      expect(events).to eq [:unlink, ['rm /tmp/5.sock', threads.first]]
    end

    it 'gives the pid of the process that stopped, after bluepill forgets it' do
      process.stop_process
      process.clear_pid
      process.post_stop_command = 'rm /tmp/{{PID}}.sock'
      process.post_stop_process.join
      expect(Bluepill::System).to have_received(:execute_blocking).with('rm /tmp/5.sock', anything)
      expect(logger).to have_received(:info).with('Executing post stop command: rm /tmp/5.sock')
    end

    it 'does nothing without a post stop command' do
      threads = capture_threads
      process.stop_process
      expect(threads).to be_empty
      expect(process.post_stop_process).to be_nil
    end
  end

  describe '#notify_transition' do
    let(:transition) { Bluepill::Process::Transition.new(:up, :restarting) }

    before { process.notify_command = 'alert {{PID}}' }

    it 'runs the notify command in the background, with the details in its environment' do
      process.app_name = 'app'
      process.group_name = 'web'
      run_process
      process.instance_variable_set(:@transition_reason, 'mem_usage: [1.2GB*]')
      process.notify_transition(transition).join
      expect(Bluepill::System).to have_received(:execute_blocking).with(
        'alert 5',
        hash_including(
          environment: {
            'BLUEPILL_APP' => 'app',
            'BLUEPILL_GROUP' => 'web',
            'BLUEPILL_PROCESS' => 'proc_name',
            'BLUEPILL_FROM' => 'up',
            'BLUEPILL_TO' => 'restarting',
            'BLUEPILL_REASON' => 'mem_usage: [1.2GB*]',
            'BLUEPILL_PID' => '5',
          }
        )
      )
      expect(logger).to have_received(:info).with('Executing notify command: alert 5')
    end

    it 'gives the last pid of a process that died, and empty values for what it lacks' do
      run_process
      process.clear_pid
      process.notify_transition(transition).join
      expect(Bluepill::System).to have_received(:execute_blocking).with(
        'alert 5',
        hash_including(environment: hash_including('BLUEPILL_APP' => '', 'BLUEPILL_GROUP' => '', 'BLUEPILL_REASON' => '', 'BLUEPILL_PID' => '5'))
      )
    end

    it 'gives no pid before the process has one' do
      process.notify_transition(transition).join
      expect(Bluepill::System).to have_received(:execute_blocking).with('alert ', hash_including(environment: hash_including('BLUEPILL_PID' => '')))
    end

    it 'does nothing for a loopback' do
      expect(process.notify_transition(Bluepill::Process::Transition.new(:up, :up))).to be_nil
    end

    it 'does nothing without a notify command' do
      process.notify_command = nil
      expect(process.notify_transition(transition)).to be_nil
    end

    it "runs on each change of state, with the event's reason" do
      threads = capture_threads
      process.state = 'up'
      process.dispatch!(:stop, 'user initiated')
      threads.each(&:join)
      expect(Bluepill::System).to have_received(:execute_blocking).with(
        'alert ',
        hash_including(environment: hash_including('BLUEPILL_FROM' => 'up', 'BLUEPILL_TO' => 'stopping', 'BLUEPILL_REASON' => 'user initiated'))
      )
      expect(process.instance_variable_get(:@transition_reason)).to be_nil
    end

    it 'forgets the reason even when the transition raises' do
      process.state = 'up'
      allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).and_raise('boom')
      expect { process.dispatch!(:stop, 'user initiated') }.to raise_error('boom')
      expect(process.instance_variable_get(:@transition_reason)).to be_nil
    end
  end
end
