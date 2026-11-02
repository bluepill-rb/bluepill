require 'tmpdir'

describe Bluepill::Process do
  let(:logger) { instance_double(Bluepill::Logger).as_null_object }
  let(:now) { Time.at(1_000_000) }

  subject do
    Bluepill::Process.new(:proc_name, [], logger: logger)
  end

  before do
    allow(Time).to receive(:now).and_return(now)
    allow(Bluepill::Clock).to receive(:now).and_return(now.to_i)
    allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal)
    allow(Bluepill::ProcessJournal).to receive(:append_pid_to_journal)
    allow(::Process).to receive(:kill).and_return(1)
  end

  def watch_double(name, events)
    double(name.to_s, name: name, run: events, to_s: name.to_s, clear_history!: nil, :logger= => nil)
  end

  describe '#initialize' do
    context 'defaults' do
      [
        :start_command, :stop_command, :restart_command, :stdout, :stderr, :stdin,
        :daemonize, :pid_file, :working_dir, :uid, :gid, :child_process_factory,
        :pid_command, :auto_start, :supplementary_groups, :stop_signals
      ].each do |attr|
        describe attr do
          subject { super().send(attr) }
          it { should be_nil }
        end
      end

      describe '#monitor_children' do
        subject { super().monitor_children }
        it { should be false }
      end

      describe '#cache_actual_pid' do
        subject { super().cache_actual_pid }
        it { should be true }
      end

      describe '#start_grace_time' do
        subject { super().start_grace_time }
        it { should eq 3 }
      end

      describe '#stop_grace_time' do
        subject { super().stop_grace_time }
        it { should eq 3 }
      end

      describe '#restart_grace_time' do
        subject { super().restart_grace_time }
        it { should eq 3 }
      end

      describe '#on_start_timeout' do
        subject { super().on_start_timeout }
        it { should eq 'start' }
      end

      describe '#environment' do
        subject { super().environment }
        it { should eq({}) }
      end

      describe '#state' do
        subject { super().state }
        it { should eq 'unmonitored' }
      end

      [:group_start_noblock, :group_stop_noblock, :group_restart_noblock, :group_unmonitor_noblock].each do |attr|
        describe attr do
          subject { super().send(attr) }
          it { should be true }
        end
      end
    end

    it 'works without options' do
      process = Bluepill::Process.new(:proc_name, [])
      expect(process.name).to eq :proc_name
      expect(process.children).to eq []
      expect(process.statistics).to be_a(Bluepill::ProcessStatistics)
      expect(process.statistics.events.size).to eq 0
      expect(process.instance_variable_get(:@threads)).to eq []
      expect(process.instance_variable_get(:@event_mutex)).to be_a(Monitor)
    end

    context 'overrides' do
      subject { Bluepill::Process.new(:proc_name, [], start_grace_time: 17) }

      describe '#start_grace_time' do
        subject { super().start_grace_time }
        it { should eq 17 }
      end
    end

    context 'with checks' do
      subject do
        Bluepill::Process.new(:proc_name, {flapping: {times: 2}, mem_usage: {below: 100, every: 10}}, logger: logger)
      end

      it 'adds triggers and watches' do
        expect(subject.triggers.size).to eq 1
        expect(subject.triggers.first).to be_a(Bluepill::Triggers::Flapping)
        expect(subject.triggers.first.logger).to eq logger
        expect(subject.triggers.first.times).to eq 2
        expect(subject.triggers.first.process).to be subject
        expect(subject.watches.size).to eq 1
        expect(subject.watches.first.name).to eq :mem_usage
        expect(subject.watches.first.logger).to eq logger
        expect(subject.watches.first.instance_variable_get(:@every)).to eq 10
      end

      it 'propagates a new logger to watches and triggers' do
        new_logger = instance_double(Bluepill::Logger).as_null_object
        subject.logger = new_logger
        expect(subject.logger).to eq new_logger
        expect(subject.watches.first.logger).to eq new_logger
        expect(subject.triggers.first.logger).to eq new_logger
      end
    end

    it 'accepts an actual pid' do
      process = Bluepill::Process.new(:proc_name, [], logger: logger, actual_pid: 42)
      expect(process.actual_pid).to eq 42
    end
  end

  describe '#tick' do
    it 'logs an error, such as a trigger raised, and keeps ticking' do
      trigger = double('trigger', :logger= => nil)
      subject.triggers << trigger
      error = RuntimeError.new('boom')
      error.set_backtrace(['line 1'])
      allow(trigger).to receive(:notify).and_raise(error)
      subject.state = 'down'
      allow(subject).to receive(:process_running?).and_return(true)
      expect(logger).to receive(:err).with('tick failed: RuntimeError: boom').ordered
      expect(logger).to receive(:err).with('line 1').ordered
      expect { subject.tick }.not_to raise_error
      expect(subject).to be_down
    end

    it 'does nothing while skipping ticks' do
      subject.skip_ticks_until = now.to_i + 10
      expect(subject).not_to receive(:clean_threads)
      subject.tick
      expect(subject.skip_ticks_until).to eq now.to_i + 10
    end

    it 'rechecks whether the process is running on every tick' do
      subject.state = 'up'
      subject.actual_pid = 5
      subject.process_running = true
      allow(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH)
      expect(subject).not_to receive(:run_watches)
      subject.tick
      expect(subject).to be_down
    end

    it 'cleans threads when unmonitored and stays unmonitored' do
      subject.skip_ticks_until = now.to_i - 1
      expect(subject).to receive(:clean_threads)
      subject.tick
      expect(subject.skip_ticks_until).to be_nil
      expect(subject).to be_unmonitored
    end

    it 'transitions from down to starting when not running' do
      subject.state = 'down'
      allow(subject).to receive(:process_running?).and_return(false)
      expect(subject).to receive(:start_process)
      expect(subject).not_to receive(:clean_threads)
      expect(subject).not_to receive(:run_watches)
      subject.tick
      expect(subject).to be_starting
    end

    it 'transitions from down to up when running, and runs watches' do
      subject.state = 'down'
      allow(subject).to receive(:process_running?).and_return(true)
      expect(subject).to receive(:run_watches)
      expect(subject).not_to receive(:refresh_children!)
      subject.tick
      expect(subject).to be_up
    end

    it 'ticks children when monitoring children' do
      child = double('child')
      subject.state = 'up'
      subject.monitor_children = true
      allow(subject).to receive(:process_running?).and_return(true)
      allow(subject).to receive(:run_watches)
      expect(subject).to receive(:refresh_children!) { subject.children << child }
      expect(child).to receive(:tick)
      subject.tick
      expect(subject).to be_up
    end

    {
      'starting' => %w[up down],
      'up' => %w[up down],
      'stopping' => %w[up down],
      'restarting' => %w[up down],
    }.each do |from, (running_to, stopped_to)|
      it "transitions from #{from} to #{running_to} when running" do
        subject.state = from
        allow(subject).to receive(:process_running?).and_return(true)
        allow(subject).to receive(:run_watches)
        subject.tick
        expect(subject.state).to eq running_to
      end

      it "transitions from #{from} to #{stopped_to} when not running" do
        subject.state = from
        allow(subject).to receive(:process_running?).and_return(false)
        subject.tick
        expect(subject.state).to eq stopped_to
      end
    end
  end

  describe 'events' do
    it 'starts the process on start' do
      expect(subject).to receive(:start_process)
      subject.dispatch!(:start, 'reason')
      expect(subject).to be_starting
      expect(subject.statistics.events.first[0, 2]).to eq [:start, 'reason']
    end

    it 'handles one event at a time' do
      allow(subject).to receive(:start_process)
      expect(subject.instance_variable_get(:@event_mutex)).to receive(:synchronize).and_call_original
      subject.dispatch!('start')
      expect(subject).to be_starting
    end

    it 'stops the process on stop' do
      subject.state = 'up'
      expect(subject).to receive(:stop_process)
      subject.dispatch!(:stop)
      expect(subject).to be_stopping
    end

    it 'restarts the process on restart' do
      subject.state = 'down'
      expect(subject).to receive(:restart_process)
      subject.dispatch!(:restart)
      expect(subject).to be_restarting
    end

    it 'cleans threads when leaving stopping' do
      subject.state = 'stopping'
      expect(subject).to receive(:clean_threads)
      subject.dispatch!(:unmonitor)
      expect(subject).to be_unmonitored
    end
  end

  describe '#record_transition' do
    it 'ignores loopback transitions' do
      transition = double('transition', loopback?: true)
      expect(logger).not_to receive(:info)
      subject.record_transition(transition)
      expect(subject.instance_variable_get(:@transitioned)).to be_nil
    end

    it 'clears watch history and logs' do
      watch = watch_double(:w, [])
      subject.watches << watch
      transition = double('transition', loopback?: false, from_name: :up, to_name: :down)
      expect(watch).to receive(:clear_history!)
      expect(logger).to receive(:info).with('Going from up => down')
      expect(logger).not_to receive(:warning)
      subject.record_transition(transition)
      expect(subject.instance_variable_get(:@transitioned)).to be true
    end

    it 'clears the child list when monitoring children' do
      subject.monitor_children = true
      subject.children << double('child')
      transition = double('transition', loopback?: false, from_name: :up, to_name: :down)
      expect(logger).to receive(:warning).with('Clearing child list')
      subject.record_transition(transition)
      expect(subject.children).to be_empty
    end
  end

  describe '#notify_triggers' do
    let(:transition) { double('transition') }
    let(:trigger) { double('trigger', :logger= => nil) }

    before { subject.triggers << trigger }

    it 'notifies each trigger' do
      expect(trigger).to receive(:notify).with(transition)
      subject.notify_triggers(transition)
    end

    it 're-raises errors, for tick to log' do
      error = RuntimeError.new('boom')
      allow(trigger).to receive(:notify).and_raise(error)
      expect(logger).not_to receive(:err)
      expect { subject.notify_triggers(transition) }.to raise_error(error)
    end
  end

  describe '#add_trigger' do
    it 'adds bluepill\'s own trigger as it is' do
      subject.add_trigger(:flapping, times: 2)
      expect(subject.triggers.first).to be_an_instance_of(Bluepill::Triggers::Flapping)
      expect(subject.triggers.first.process).to be subject
      expect(subject.triggers.first.logger).to be logger
    end

    it 'wraps a trigger that a config defines, so its transitions warn about what 0.2.0 drops' do
      # A subclass of Flapping, which is a trigger of its own. Anonymous, so
      # it isn't registered.
      allow(Bluepill::Trigger).to receive(:inherited)
      custom = Class.new(Bluepill::Triggers::Flapping)
      allow(Bluepill::Trigger).to receive(:[]).with(:custom).and_return(custom)
      subject.add_trigger(:custom, times: 2)
      expect(subject.triggers.first).to be_an_instance_of(Bluepill::Trigger::Custom)
      expect(subject.triggers.first.trigger).to be_an_instance_of(custom)
      expect(subject.triggers.first.trigger.times).to eq 2
      expect(subject.triggers.first.trigger.logger).to be logger
    end
  end

  describe '#add_watch' do
    it 'adds a condition watch' do
      subject.add_watch(:mem_usage, below: 10)
      expect(subject.watches.first).to be_a(Bluepill::ConditionWatch)
      expect(subject.watches.first.logger).to eq logger
    end
  end

  describe '#run_watches' do
    before { subject.actual_pid = 5 }

    it 'dispatches events from watches' do
      quiet = watch_double(:quiet, [])
      loud = watch_double(:loud, [:restart, :stop])
      allow(loud).to receive(:to_s).and_return('loud: [1, 2]')
      subject.watches << quiet << loud
      expect(quiet).to receive(:run).with(5, now.to_i).and_return([])
      expect(logger).to receive(:info).once.with('loud dispatched: restart,stop')
      expect(logger).not_to receive(:info).with('quiet dispatched: ')
      expect(subject).to receive(:dispatch!).with(:restart, 'loud: [1, 2]').ordered
      expect(subject).to receive(:dispatch!).with(:stop, 'loud: [1, 2]').ordered
      subject.run_watches
    end

    it 'dispatches after a transition in an earlier run' do
      subject.instance_variable_set(:@transitioned, true)
      subject.watches << watch_double(:loud, [:restart])
      expect(subject).to receive(:dispatch!).with(:restart, 'loud')
      subject.run_watches
    end

    it 'stops dispatching after a transition' do
      subject.watches << watch_double(:loud, [:restart, :stop])
      expect(subject).to receive(:dispatch!).once.with(:restart, 'loud') do
        subject.instance_variable_set(:@transitioned, true)
      end
      subject.run_watches
    end
  end

  describe '#determine_initial_state' do
    it 'is up when running' do
      expect(subject).to receive(:process_running?).with(true).and_return(true)
      subject.determine_initial_state
      expect(subject.state).to eq 'up'
    end

    it 'is unmonitored when auto_start is false' do
      allow(subject).to receive(:process_running?).and_return(false)
      subject.auto_start = false
      subject.determine_initial_state
      expect(subject.state).to eq 'unmonitored'
    end

    it 'is down otherwise' do
      allow(subject).to receive(:process_running?).and_return(false)
      subject.determine_initial_state
      expect(subject.state).to eq 'down'
    end
  end

  describe '#handle_user_command' do
    it 'refuses to start a running process' do
      allow(subject).to receive(:process_running?).with(true).and_return(true)
      expect(logger).to receive(:warning).with('Refusing to re-run start command on an already running process.')
      expect(subject).not_to receive(:dispatch!)
      subject.handle_user_command('start')
    end

    it 'starts a stopped process' do
      allow(subject).to receive(:process_running?).with(true).and_return(false)
      expect(subject).to receive(:dispatch!).with(:start, 'user initiated')
      subject.handle_user_command('start')
    end

    it 'stops and unmonitors' do
      expect(subject).to receive(:stop_process)
      expect(subject).to receive(:dispatch!).with(:unmonitor, 'user initiated')
      subject.handle_user_command('stop')
    end

    it 'restarts through the state machine' do
      expect(subject).to receive(:dispatch!).with(:restart, 'user initiated').and_return(true)
      expect(subject).not_to receive(:restart_process)
      subject.handle_user_command('restart')
    end

    it 'restarts an up process by going to restarting' do
      subject.state = 'up'
      expect(subject).to receive(:restart_process)
      subject.handle_user_command('restart')
      expect(subject.state).to eq('restarting')
    end

    it 'restarts directly from a state restart cannot leave' do
      subject.state = 'unmonitored'
      expect(subject).to receive(:restart_process)
      subject.handle_user_command('restart')
      expect(subject.state).to eq('unmonitored')
    end

    it 'resets triggers and unmonitors' do
      trigger = double('trigger', :logger= => nil)
      subject.triggers << trigger
      expect(trigger).to receive(:reset!)
      expect(subject).to receive(:dispatch!).with(:unmonitor, 'user initiated')
      subject.handle_user_command('unmonitor')
    end

    it 'ignores unknown commands' do
      expect(subject).not_to receive(:dispatch!)
      expect(subject.handle_user_command('bogus')).to be_nil
    end
  end

  describe 'predicates' do
    it 'are false, not nil, for unset attributes' do
      subject.cache_actual_pid = nil
      subject.monitor_children = nil
      expect(subject.cache_actual_pid?).to be false
      expect(subject.monitor_children?).to be false
      expect(subject.daemonize?).to be false
    end

    it 'are true, not the attribute, for set attributes' do
      subject.cache_actual_pid = 1
      subject.monitor_children = 1
      subject.daemonize = 1
      expect(subject.cache_actual_pid?).to be true
      expect(subject.monitor_children?).to be true
      expect(subject.daemonize?).to be true
    end
  end

  describe '#process_running?' do
    before { subject.actual_pid = 5 }

    it 'memoizes a running result' do
      expect(subject).to receive(:signal_process).once.with(0).and_return(true)
      expect(subject.process_running?).to be true
      expect(subject.process_running?).to be true
      expect(subject.actual_pid).to eq 5
    end

    it 'rechecks when forced' do
      expect(subject).to receive(:signal_process).twice.with(0).and_return(true)
      subject.process_running?
      subject.process_running?(true)
    end

    it 'clears the pid when not running' do
      allow(subject).to receive(:signal_process).with(0).and_return(false)
      expect(subject.process_running?).to be false
      expect(subject.instance_variable_get(:@actual_pid)).to be_nil
    end
  end

  describe '#start_process' do
    before { subject.start_command = '/etc/init.d/script start' }

    it 'functions' do
      allow(subject).to receive(:on_start_timeout) { 'freakout' }
      allow(subject).to receive(:daemonize?) { false }

      expect(subject).to receive(:with_timeout).
        with(3, 'freakout').
        and_yield

      expect(Bluepill::System).to receive(:execute_blocking).
        with('/etc/init.d/script start', subject.system_command_options).
        and_return(exit_code: 0)
      expect(logger).to receive(:warning).with('Executing start command: /etc/init.d/script start')

      subject.start_process
      expect(subject.skip_ticks_until).to eq now.to_i + 3
    end

    it 'runs the pre start command first' do
      subject.pre_start_command = 'prepare'
      expect(Bluepill::System).to receive(:execute_blocking).
        with('prepare', anything).ordered.
        and_return(exit_code: 0)
      expect(Bluepill::System).to receive(:execute_blocking).
        with('/etc/init.d/script start', anything).ordered.
        and_return(exit_code: 0)
      subject.start_process
    end

    it 'warns on a non-zero exit code' do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 1)
      expect(logger).to receive(:warning).with('Start command execution returned non-zero exit code:')
      expect(logger).to receive(:warning).with({exit_code: 1}.inspect)
      subject.start_process
    end

    it 'warns when a signal killed the command' do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: nil)
      expect(logger).to receive(:warning).with('Start command execution returned non-zero exit code:')
      expect(logger).to receive(:warning).with({exit_code: nil}.inspect)
      subject.start_process
    end

    it 'kills a stop signal thread left from an earlier stop' do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 0)
      stop_thread = Thread.new { sleep }
      subject.instance_variable_get(:@threads) << stop_thread
      subject.start_process
      stop_thread.join(1)
      expect(stop_thread).not_to be_alive
      expect(subject.instance_variable_get(:@threads)).to be_empty
    end

    context 'when daemonizing' do
      before { subject.daemonize = true }

      it 'journals the daemon pid' do
        expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).with(:proc_name)
        expect(Bluepill::System).to receive(:daemonize).
          with('/etc/init.d/script start', subject.system_command_options).
          and_return(99)
        expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 99)
        subject.start_process
      end

      it 'journals children pids when monitoring children' do
        subject.monitor_children = true
        subject.children << double('child', actual_pid: 100)
        allow(Bluepill::System).to receive(:daemonize).and_return(99)
        expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 99)
        expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 100)
        subject.start_process
      end

      it 'does not journal when daemonizing fails' do
        allow(Bluepill::System).to receive(:daemonize).and_return(nil)
        expect(Bluepill::ProcessJournal).not_to receive(:append_pid_to_journal)
        subject.start_process
      end
    end
  end

  describe '#pre_start_process' do
    it 'does nothing without a pre start command' do
      expect(Bluepill::System).not_to receive(:execute_blocking)
      subject.pre_start_process
    end

    context 'with a pre start command' do
      before { subject.pre_start_command = 'prepare' }

      it 'executes it' do
        expect(Bluepill::System).to receive(:execute_blocking).
          with('prepare', subject.system_command_options).
          and_return(exit_code: 0)
        expect(logger).to receive(:warning).once.with('Executing pre start command: prepare')
        expect(logger).not_to receive(:warning).with('Pre start command execution returned non-zero exit code:')
        subject.pre_start_process
      end

      it 'warns on a non-zero exit code' do
        allow(Bluepill::System).to receive(:execute_blocking).and_return(exit_code: 2)
        expect(logger).to receive(:warning).with('Pre start command execution returned non-zero exit code:')
        subject.pre_start_process
      end
    end
  end

  describe '#stop_process' do
    before { subject.actual_pid = 5 }

    it 'functions' do
      allow(subject).to receive(:stop_command) { '/etc/init.d/script stop' }
      expect(subject).to receive(:with_timeout).
        with(3, 'stop').
        and_yield

      expect(Bluepill::System).to receive(:execute_blocking).
        with('/etc/init.d/script stop', subject.system_command_options).
        and_return(exit_code: 0)

      subject.stop_process
    end

    it 'substitutes the pid and warns on a non-zero exit code' do
      subject.stop_command = 'kill {{PID}}; wait {{PID}}'
      subject.pid_file = 'some.pid'
      expect(Bluepill::System).not_to receive(:get_children)
      expect(Bluepill::System).to receive(:execute_blocking).
        with('kill 5; wait 5', anything).
        and_return(exit_code: 1)
      expect(logger).to receive(:warning).with('Executing stop command: kill 5; wait 5').ordered
      expect(logger).to receive(:warning).with('Stop command execution returned non-zero exit code:').ordered
      expect(Bluepill::ProcessJournal).to receive(:kill_all_from_journal).with(:proc_name)
      expect(Bluepill::System).to receive(:delete_if_exists).with('some.pid')
      subject.stop_process
    end

    it 'journals children when monitoring children' do
      subject.monitor_children = true
      allow(Bluepill::System).to receive(:delete_if_exists)
      expect(Bluepill::System).to receive(:get_children).with(5).and_return([6, 7])
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 6)
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 7)
      subject.stop_process
    end

    it 'journals no children when stopped before it has a pid' do
      subject.clear_pid
      subject.monitor_children = true
      allow(Bluepill::System).to receive(:ps_axu).and_return(0 => %w[PID PPID %CPU RSS ELAPSED COMMAND])
      allow(Bluepill::System).to receive(:delete_if_exists)
      expect(Bluepill::ProcessJournal).not_to receive(:append_pid_to_journal)
      subject.stop_process
    end

    it 'sends TERM by default' do
      expect(logger).to receive(:warning).with('Executing default stop command. Sending TERM signal to 5')
      expect(::Process).to receive(:kill).with('TERM', 5)
      expect(Bluepill::System).to receive(:delete_if_exists).with(nil)
      subject.stop_process
      expect(subject.skip_ticks_until).to eq now.to_i + 3
    end

    context 'with stop signals' do
      before do
        allow(Bluepill::System).to receive(:delete_if_exists)
        allow(subject).to receive(:sleep)
      end

      def run_stop_signals
        subject.stop_process
        subject.instance_variable_get(:@threads).each(&:join)
      end

      it 'sends a single signal' do
        subject.stop_signals = [:quit]
        expect(logger).to receive(:warning).with('Sending stop signals to 5')
        expect(logger).to receive(:info).with('Sending signal quit to 5')
        expect(::Process).to receive(:kill).with('QUIT', 5)
        expect(subject).to receive(:cleanup_process)
        run_stop_signals
      end

      it 'sends each signal with a delay while the process is alive' do
        subject.stop_signals = [:quit, 2, :term, 3, :kill]
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
        expect(subject).to receive(:sleep).with(2)
        expect(subject).to receive(:sleep).with(3)
        run_stop_signals
        expect(subject.stop_signals).to eq [:quit, 2, :term, 3, :kill]
      end

      it 'stops once the process has terminated' do
        subject.stop_signals = [:quit, 2, :kill]
        expect(::Process).to receive(:kill).with('QUIT', 5)
        expect(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH)
        expect(::Process).not_to receive(:kill).with('KILL', 5)
        expect(logger).to receive(:debug).with('Process has terminated.')
        expect(subject).to receive(:cleanup_process).once
        run_stop_signals
      end

      it 'rounds a fractional wait up to whole seconds' do
        subject.stop_signals = [:quit]
        subject.stop_grace_time = 4.5
        expect(::Process).to receive(:kill).with(0, 5).exactly(3).times
        expect(subject).to receive(:sleep).with(1).exactly(3).times
        run_stop_signals
      end

      it 'waits for the process to exit before cleaning up' do
        subject.stop_signals = [:quit]
        subject.stop_grace_time = 5
        expect(::Process).to receive(:kill).with('QUIT', 5).ordered
        expect(::Process).to receive(:kill).with(0, 5).exactly(3).times.ordered
        expect(subject).to receive(:sleep).with(1).exactly(3).times
        expect(subject).to receive(:cleanup_process).ordered
        run_stop_signals
      end

      it 'cleans up as soon as the process exits after the last signal' do
        subject.stop_signals = [:quit, 2, :term]
        subject.stop_grace_time = 10
        alive = [1, 1]
        allow(::Process).to receive(:kill).with(0, 5) { alive.shift || raise(Errno::ESRCH) }
        expect(::Process).to receive(:kill).with('TERM', 5)
        expect(subject).to receive(:sleep).with(2).once
        expect(subject).to receive(:sleep).with(1).once
        expect(subject).to receive(:cleanup_process)
        run_stop_signals
      end
    end
  end

  describe '#restart_process' do
    it 'functions' do
      allow(subject).to receive(:restart_command) { '/etc/init.d/script restart' }
      expect(subject).to receive(:with_timeout).
        with(3, 'restart').
        and_yield

      expect(Bluepill::System).to receive(:execute_blocking).
        with('/etc/init.d/script restart', subject.system_command_options).
        and_return(exit_code: 0)

      subject.restart_process
      expect(subject.skip_ticks_until).to eq now.to_i + 3
    end

    it 'substitutes the pid and warns on a non-zero exit code' do
      subject.restart_command = 'restart {{PID}}'
      subject.actual_pid = 5
      expect(Bluepill::System).to receive(:execute_blocking).
        with('restart 5', anything).
        and_return(exit_code: 1)
      expect(logger).to receive(:warning).with('Executing restart command: restart 5').ordered
      expect(logger).to receive(:warning).with('Restart command execution returned non-zero exit code:').ordered
      subject.restart_process
    end

    it 'stops and starts without a restart command' do
      expect(logger).to receive(:warning).with('No restart_command specified. Must stop and start to restart')
      expect(subject).to receive(:stop_process).ordered
      expect(subject).to receive(:start_process).ordered
      subject.restart_process
    end

    it 'waits for the stop signals to finish before starting' do
      subject.actual_pid = 5
      subject.stop_signals = [:quit, 1, :kill]
      allow(Bluepill::System).to receive(:delete_if_exists)
      allow(subject).to receive(:sleep) { Kernel.sleep(0.1) }
      events = []
      allow(::Process).to receive(:kill) { |signal, _pid| events << signal }
      allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal) { events << :cleanup }
      allow(subject).to receive(:start_process) { events << :start }
      subject.restart_process
      expect(events).to eq ['QUIT', 0, 'KILL', :cleanup, :start]
    end
  end

  describe '#clean_threads' do
    it 'kills and clears threads' do
      thread = double('thread')
      subject.instance_variable_get(:@threads) << thread
      expect(thread).to receive(:kill)
      subject.clean_threads
      expect(subject.instance_variable_get(:@threads)).to be_empty
    end
  end

  describe '#signal_process' do
    before { subject.actual_pid = 5 }

    it 'upcases string signals' do
      expect(::Process).to receive(:kill).with('HUP', 5)
      expect(subject.signal_process('hup')).to be true
    end

    it 'upcases strings of a String subclass' do
      expect(::Process).to receive(:kill).with('HUP', 5)
      expect(subject.signal_process(Class.new(String).new('hup'))).to be true
    end

    it 'turns symbol signals into upcased strings' do
      expect(::Process).to receive(:kill).with('HUP', 5)
      expect(subject.signal_process(:hup)).to be true
    end

    it 'signals pid 1' do
      subject.actual_pid = 1
      expect(::Process).to receive(:kill).with(0, 1)
      expect(subject.signal_process(0)).to be true
    end

    it 'passes integer signals through' do
      expect(::Process).to receive(:kill).with(9, 5)
      expect(subject.signal_process(9)).to be true
    end

    it 'logs and returns false on failure' do
      allow(::Process).to receive(:kill).and_raise(Errno::EPERM)
      expect(logger).to receive(:err).with(/Failed to signal process 5 with code 0/)
      expect(subject.signal_process(0)).to be false
    end

    it 'never signals a pid of 0 or less' do
      [0, -1].each do |pid|
        subject.instance_variable_set(:@actual_pid, pid)
        expect(logger).to receive(:err).with("Failed to signal process #{pid} with code 0: invalid pid #{pid}")
        expect(subject.signal_process(0)).to be false
      end
      expect(::Process).not_to have_received(:kill)
    end

    it 'returns false without an error when there is no pid' do
      subject.instance_variable_set(:@actual_pid, nil)
      allow(logger).to receive(:err)
      expect(subject.signal_process(0)).to be false
      expect(logger).not_to have_received(:err)
      expect(::Process).not_to have_received(:kill)
    end
  end

  describe '#actual_pid' do
    it 'uses the pid command when configured' do
      subject.pid_command = 'getpid'
      expect(subject).to receive(:`).with('getpid').and_return("123\n")
      expect(subject.actual_pid).to eq 123
    end

    it 'returns nil when the pid command prints 0' do
      subject.pid_command = 'getpid'
      allow(subject).to receive(:`).and_return("0\n")
      expect(subject.actual_pid).to be_nil
    end

    it 'returns nil when the pid command output is not a number' do
      subject.pid_command = 'getpid'
      allow(subject).to receive(:`).and_return("oops\n")
      expect(subject.actual_pid).to be_nil
    end

    it 'returns nil when the pid command output only starts with a number' do
      subject.pid_command = 'getpid'
      allow(subject).to receive(:`).and_return("12 oops\n")
      expect(subject.actual_pid).to be_nil
    end

    it 'ignores whitespace and leading zeros around the pid command output' do
      subject.pid_command = 'getpid'
      allow(subject).to receive(:`).and_return("  0123\n")
      expect(subject.actual_pid).to eq 123
    end

    it 'is nil without a pid file' do
      expect(subject.actual_pid).to be_nil
    end

    context 'with a pid file' do
      around do |example|
        Dir.mktmpdir do |dir|
          @dir = dir
          example.run
        end
      end

      before { subject.pid_file = File.join(@dir, 'proc.pid') }

      it 'reads the pid and caches it' do
        File.open(subject.pid_file, 'w') { |f| f.write("77\n") }
        expect(subject.actual_pid).to eq 77
        File.open(subject.pid_file, 'w') { |f| f.write("78\n") }
        expect(subject.actual_pid).to eq 77
      end

      it 'forgets the cached pid when it cleans up after a stop' do
        File.open(subject.pid_file, 'w') { |f| f.write("77\n") }
        expect(subject.actual_pid).to eq 77
        subject.cleanup_process
        expect(File.exist?(subject.pid_file)).to be false
        File.open(subject.pid_file, 'w') { |f| f.write("78\n") }
        expect(subject.actual_pid).to eq 78
      end

      it 'rereads the pid when not caching' do
        subject.cache_actual_pid = false
        File.open(subject.pid_file, 'w') { |f| f.write("77\n") }
        expect(subject.actual_pid).to eq 77
        File.open(subject.pid_file, 'w') { |f| f.write("78\n") }
        expect(subject.actual_pid).to eq 78
      end

      it 'is nil for an empty pid file' do
        File.open(subject.pid_file, 'w') {}
        expect(subject.actual_pid).to be_nil
      end

      it 'is nil for a pid file that does not hold a positive pid' do
        subject.cache_actual_pid = false
        ["0\n", "\n", 'garbage', '-5'].each do |content|
          File.open(subject.pid_file, 'w') { |f| f.write(content) }
          expect(subject.actual_pid).to be_nil
        end
      end

      it 'is not running for a pid file that holds 0' do
        File.open(subject.pid_file, 'w') { |f| f.write("0\n") }
        allow(::Process).to receive(:kill).and_call_original
        expect(subject.process_running?(true)).to be false
      end

      it 'reads pid 1' do
        File.open(subject.pid_file, 'w') { |f| f.write("1\n") }
        expect(subject.actual_pid).to eq 1
      end

      it 'warns when the pid file does not exist' do
        expect(logger).to receive(:warning).with("pid_file #{subject.pid_file} does not exist or cannot be read")
        expect(subject.actual_pid).to be_nil
      end
    end
  end

  describe '#actual_pid=' do
    it 'journals the pid' do
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 12)
      subject.actual_pid = 12
      expect(subject.actual_pid).to eq 12
    end
  end

  describe '#skip_ticks_for' do
    it 'adds to an existing skip' do
      subject.skip_ticks_until = now.to_i + 5
      subject.skip_ticks_for(2.5)
      expect(subject.skip_ticks_until).to eq now.to_i + 7
    end

    it 'starts from now without a skip' do
      subject.skip_ticks_for(2)
      expect(subject.skip_ticks_until).to eq now.to_i + 2
    end
  end

  describe '#refresh_children!' do
    let(:factory) { double('factory') }
    let(:child_logger) { double('child logger') }

    before do
      subject.actual_pid = 5
      subject.child_process_factory = factory
      allow(logger).to receive(:prefix_with).and_return(child_logger)
    end

    it 'prunes dead children and adds new ones' do
      dead = double('dead', actual_pid: 6)
      alive = double('alive', actual_pid: 7)
      other = double('other', actual_pid: 9, process_running?: true)
      new_child = double('new child')
      subject.children << dead << alive << other
      expect(dead).to receive(:process_running?).with(true).and_return(false)
      expect(alive).to receive(:process_running?).with(true).and_return(true)
      expect(Bluepill::System).to receive(:get_children).with(5).and_return([7, 8, 9])
      expect(logger).to receive(:info).with('Existing children: 7,9. Got new children: [8] for 5')
      expect(logger).to receive(:prefix_with).with('<child(pid:8)>')
      expect(factory).to receive(:create_child_process).
        with('<child(pid:8)>', 8, child_logger).
        and_return(new_child)
      expect(Bluepill::ProcessJournal).not_to receive(:append_pid_to_journal)
      subject.refresh_children!
      expect(subject.children).to eq [alive, other, new_child]
    end

    it 'journals new children when daemonized' do
      subject.daemonize = true
      allow(Bluepill::System).to receive(:get_children).and_return([8])
      allow(factory).to receive(:create_child_process).and_return(double('child'))
      expect(Bluepill::ProcessJournal).to receive(:append_pid_to_journal).with(:proc_name, 8)
      subject.refresh_children!
    end

    it 'does nothing without new children' do
      allow(Bluepill::System).to receive(:get_children).and_return([])
      expect(logger).not_to receive(:info)
      subject.refresh_children!
      expect(subject.children).to be_empty
    end
  end

  describe '#with_timeout' do
    let(:block) { proc { nil } }

    it 'returns the result of the block' do
      expect(subject.with_timeout(3, 'state_override') { :done }).to eq :done
    end

    it 'proceeds to next_state on timeout.' do
      expect(Timeout).to receive(:timeout).with(3, &block).and_raise(Timeout::Error)
      expect(logger).to receive(:err).with('Execution is taking longer than expected.').ordered
      expect(logger).to receive(:err).with('Did you forget to tell bluepill to daemonize this process?').ordered
      expect(subject).to receive(:dispatch!).with('state_override')
      subject.with_timeout(3, 'state_override', &block)
    end

    it 'times out after a fraction of a second' do
      expect(subject).to receive(:dispatch!).with('state_override')
      subject.with_timeout(0.01, 'state_override') { Kernel.sleep 1 }
    end
  end

  describe '#system_command_options' do
    it 'passes the process settings to the command' do
      subject.uid = 'user'
      subject.gid = 'group'
      subject.working_dir = '/work'
      subject.environment = {'A' => 'b'}
      subject.pid_file = 'proc.pid'
      subject.stdin = 'in'
      subject.stdout = 'out'
      subject.stderr = 'err'
      subject.supplementary_groups = ['extra']
      expect(subject.system_command_options).to eq(
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
end
