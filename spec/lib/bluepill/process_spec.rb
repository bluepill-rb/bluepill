describe Bluepill::Process do
  before(:all) do
    Bluepill::ProcessJournal.base_dir = './.bluepill'
    Bluepill::ProcessJournal.logger = Bluepill::Logger.new(log_file: 'bluepill.log', stdout: false).prefix_with('rspec')
  end

  subject do
    Bluepill::Process.new(:proc_name, [], logger: Bluepill::Logger.new)
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
        it { should eq Hash[] }
      end
    end

    context 'overrides' do
      subject { Bluepill::Process.new(:proc_name, [], start_grace_time: 17) }

      describe '#start_grace_time' do
        subject { super().start_grace_time }
        it { should eq 17 }
      end
    end
  end

  describe '#start_process' do
    it 'functions' do
      allow(subject).to receive(:start_command) { '/etc/init.d/script start' }
      allow(subject).to receive(:on_start_timeout) { 'freakout' }
      allow(subject.logger).to receive(:warning)
      allow(subject).to receive(:daemonize?) { false }

      expect(subject).to receive(:with_timeout).
        with(3, 'freakout').
        and_yield

      expect(Bluepill::System).to receive(:execute_blocking).
        with('/etc/init.d/script start', subject.system_command_options).
        and_return(exit_code: 0)

      subject.start_process
    end

    describe '#stop_process' do
      it 'functions' do
        allow(subject).to receive(:stop_command) { '/etc/init.d/script stop' }
        allow(subject.logger).to receive(:warning)
        expect(subject).to receive(:with_timeout).
          with(3, 'stop').
          and_yield

        expect(Bluepill::System).to receive(:execute_blocking).
          with('/etc/init.d/script stop', subject.system_command_options).
          and_return(exit_code: 0)

        subject.stop_process
      end
    end

    describe '#restart_process' do
      it 'functions' do
        allow(subject).to receive(:restart_command) { '/etc/init.d/script restart' }
        allow(subject.logger).to receive(:warning)
        expect(subject).to receive(:with_timeout).
          with(3, 'restart').
          and_yield

        expect(Bluepill::System).to receive(:execute_blocking).
          with('/etc/init.d/script restart', subject.system_command_options).
          and_return(exit_code: 0)

        subject.restart_process
      end
    end
  end

  describe '#with_timeout' do
    let(:block) { proc { nil } }

    before(:each) do
      allow(subject.logger).to receive(:err)
      expect(Timeout).to receive(:timeout).with(3.to_f, &block).and_raise(Timeout::Error)
    end

    it 'proceeds to next_state on timeout.' do
      expect(subject).to receive(:dispatch!).with('state_override')
      subject.with_timeout(3, 'state_override', &block)
    end
  end
end
