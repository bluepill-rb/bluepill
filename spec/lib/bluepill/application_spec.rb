require 'tmpdir'

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger, debug: nil, err: nil, reopen: nil) }
  let(:traps) { {} }

  before do
    allow(logger).to receive(:prefix_with).and_return(logger)
    allow(Bluepill::Logger).to receive(:new).and_return(logger)
    allow(Bluepill::ProcessJournal).to receive(:setup)
    allow(Bluepill::ProcessJournal).to receive(:logger=)
    allow(Signal).to receive(:trap) { |signal, &block| traps[signal] = block }
  end

  describe '#initialize' do
    let(:options) { {} }
    subject { described_class.new('test', options) }

    before { expect_any_instance_of(described_class).to receive(:setup_pids_dir) }

    context 'when euid is not root' do
      before { allow(::Process).to receive(:euid).and_return(1) }

      describe '#base_dir' do
        subject { super().base_dir }

        it { is_expected.to eq(File.join(ENV.fetch('HOME', nil), '.bluepill')) }
      end
    end
    context 'when euid is root' do
      before { allow(::Process).to receive(:euid).and_return(0) }

      describe '#base_dir' do
        subject { super().base_dir }

        it { is_expected.to eq('/var/run/bluepill') }
      end

      it 'does not need HOME' do
        home = ENV.delete('HOME')
        begin
          expect(subject.base_dir).to eq('/var/run/bluepill')
        ensure
          ENV['HOME'] = home
        end
      end
    end

    context 'without options' do
      subject { described_class.new('test') }

      before { allow(::Process).to receive(:euid).and_return(0) }

      it 'uses the defaults' do
        expect(subject.base_dir).to eq('/var/run/bluepill')
        expect(subject).not_to be_foreground
      end
    end

    context 'when option base_dir is specified' do
      let(:options) { {base_dir: '/var/bluepill'} }

      describe '#base_dir' do
        subject { super().base_dir }

        it { is_expected.to eq(options[:base_dir]) }
      end

      it "gives the process journal the base dir and the app's name" do
        expect(Bluepill::ProcessJournal).to receive(:setup).with('/var/bluepill', 'test')
        subject
      end

      it 'derives the pid file and pids dir' do
        expect(subject.pid_file).to eq('/var/bluepill/pids/test.pid')
        expect(subject.pids_dir).to eq('/var/bluepill/pids/test')
      end

      it 'defaults the kill timeout and foreground mode' do
        expect(subject.kill_timeout).to eq(10)
        expect(subject).not_to be_foreground
        expect(subject.groups).to eq({})
      end

      it 'traps TERM, INT and HUP' do
        subject
        expect(traps.keys).to contain_exactly('TERM', 'INT', 'HUP')
      end

      it 'has a mutex' do
        expect(subject.mutex { :result }).to eq(:result)
      end

      context 'and foreground is false' do
        let(:options) { {base_dir: '/var/bluepill', foreground: false} }

        it { is_expected.to_not be_foreground }
      end

      it 'logs to the log file with the application name as prefix' do
        expect(Bluepill::Logger).to receive(:new).with(log_file: nil, log_level: nil, stdout: false).and_return(logger)
        expect(logger).to receive(:prefix_with).with('test').and_return(logger)
        expect(Bluepill::ProcessJournal).to receive(:logger=).with(logger)
        expect(subject.logger).to eq(logger)
      end

      context 'and other options are specified' do
        let(:options) { {base_dir: '/var/bluepill', foreground: true, log_file: 'log', log_level: :info, kill_timeout: 3} }

        it 'uses them' do
          expect(Bluepill::Logger).to receive(:new).with(log_file: 'log', log_level: :info, stdout: true).and_return(logger)
          expect(subject.kill_timeout).to eq(3)
          expect(subject.log_file).to eq('log')
          expect(subject).to be_foreground
        end
      end
    end

    context 'when environment BLUEPILL_BASE_DIR is specified' do
      around do |example|
        original = ENV.fetch('BLUEPILL_BASE_DIR', nil)
        ENV['BLUEPILL_BASE_DIR'] = '/bluepill'
        begin
          example.run
        ensure
          ENV['BLUEPILL_BASE_DIR'] = original
        end
      end

      describe '#base_dir' do
        subject { super().base_dir }

        it { is_expected.to eq(ENV.fetch('BLUEPILL_BASE_DIR', nil)) }
      end

      context 'and option base_dir is specified' do
        let(:options) { {base_dir: '/var/bluepill'} }

        describe '#base_dir' do
          subject { super().base_dir }

          it { is_expected.to eq(options[:base_dir]) }
        end
      end
    end
  end

  describe '#initialize without permission to write its files' do
    subject { described_class.new('test', base_dir: '/var/bluepill', log_file: '/var/log/bluepill.log') }

    def expect_startup_failure(message)
      expect($stderr).to receive(:puts).with("Failed to start bluepill: #{message}").ordered
      expect($stderr).to receive(:puts).with(
        'The user running bluepill must be able to write to its log_file and base_dir. ' \
        'The uid and gid in the config only apply to the processes it monitors.'
      ).ordered
      expect_any_instance_of(described_class).to receive(:exit).with(5)
    end

    it 'exits with a clear message when it cannot open the log file' do
      allow(Bluepill::Logger).to receive(:new).and_raise(Errno::EACCES, '/var/log/bluepill.log')
      expect_startup_failure('Permission denied - /var/log/bluepill.log')
      subject
    end

    it 'exits with a clear message when it cannot create the pids dir' do
      allow(File).to receive(:exist?).with('/var/bluepill/pids/test').and_return(false)
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, '/var/bluepill/pids/test')
      expect_startup_failure('Permission denied - /var/bluepill/pids/test')
      subject
    end
  end

  context 'with a base dir' do
    let(:base_dir) { Dir.mktmpdir }
    let(:foreground) { false }
    let(:app) { described_class.new('test', base_dir: base_dir, foreground: foreground) }
    let(:pids_dir) { File.join(base_dir, 'pids', 'test') }
    let(:pid_file) { File.join(base_dir, 'pids', 'test.pid') }
    let(:group) { instance_double(Bluepill::Group) }
    let(:other_group) { instance_double(Bluepill::Group) }

    after { FileUtils.remove_entry(base_dir) }

    describe 'pids dir' do
      it 'is created writable for everybody' do
        app
        expect(File.directory?(pids_dir)).to be true
        expect(File.stat(pids_dir).mode & 0o777).to eq(0o777)
      end

      it 'is made writable for everybody when it already exists' do
        FileUtils.mkdir_p(pids_dir)
        FileUtils.chmod(0o700, pids_dir)
        app
        expect(File.stat(pids_dir).mode & 0o777).to eq(0o777)
      end
    end

    describe 'signal traps' do
      before { app }

      %w[TERM INT].each do |signal|
        it "terminates on #{signal}" do
          expect(app).to receive(:puts).with('Terminating...')
          expect(app).to receive(:cleanup)
          traps[signal].call(Signal.list.fetch(signal))
          expect(app.instance_variable_get(:@running)).to be false
        end
      end

      it 'reopens the log on HUP' do
        expect(logger).to receive(:reopen)
        traps['HUP'].call
      end

      it 'ignores HUP without a logger' do
        app.logger = nil
        expect { traps['HUP'].call }.not_to raise_error
      end
    end

    describe '#mutex' do
      it 'runs the block synchronized' do
        expect(app.mutex { :result }).to eq(:result)
      end
    end

    describe '#version' do
      it 'is the bluepill version' do
        expect(app.version).to eq(Bluepill::Version)
      end
    end

    describe '#add_process' do
      let(:process) { double('process', :app_name= => nil, :group_name= => nil) }

      it 'adds the process to a new group named after the group name' do
        group_logger = instance_double(Bluepill::Logger)
        allow(logger).to receive(:prefix_with).with('web').and_return(group_logger)
        expect(Bluepill::Group).to receive(:new).with('web', logger: group_logger).and_return(group)
        expect(group).to receive(:add_process).with(process)
        app.add_process(process, :web)
        expect(app.groups).to eq('web' => group)
      end

      it 'adds processes without a group to the nil group' do
        expect(Bluepill::Group).to receive(:new).once.with(nil, logger: logger).and_return(group)
        expect(group).to receive(:add_process).with(process).twice
        app.add_process(process)
        app.add_process(process)
        expect(app.groups).to eq(nil => group)
      end

      it "tells the process its app's and group's names, for notify_command" do
        allow(logger).to receive(:prefix_with).and_return(logger)
        allow(Bluepill::Group).to receive(:new).and_return(group)
        allow(group).to receive(:add_process)
        expect(process).to receive(:app_name=).with('test')
        expect(process).to receive(:group_name=).with('web')
        app.add_process(process, :web)
      end
    end

    describe 'process commands' do
      before { app.groups = {'web' => group, 'db' => other_group} }

      described_class::PROCESS_COMMANDS.each do |command|
        describe "##{command}" do
          it 'is sent to every group without arguments' do
            expect(group).to receive(command).with(no_args).and_return(['web:a'])
            expect(other_group).to receive(command).with(no_args).and_return(['db:b'])
            expect(app.send(command)).to eq(['web:a', 'db:b'])
          end

          it 'is sent to the named group' do
            expect(group).to receive(command).with('a').and_return(['web:a'])
            expect(app.send(command, 'web', 'a')).to eq(['web:a'])
          end

          it 'is sent to every group for a process name' do
            expect(group).to receive(command).with('a').and_return(['web:a'])
            expect(other_group).to receive(command).with('a').and_return([])
            expect(app.send(command, 'a')).to eq(['web:a'])
          end

          it 'is sent to every group for a process name containing a colon' do
            expect(group).to receive(command).with('job:a').and_return(['web:job:a'])
            expect(other_group).to receive(command).with('job:a').and_return([])
            expect(app.send(command, 'job', 'a')).to eq(['web:job:a'])
          end

          it 'is sent to every group for a process name without a group' do
            expect(group).to receive(command).with('a').and_return(['web:a'])
            expect(other_group).to receive(command).with('a').and_return([])
            expect(app.send(command, nil, 'a')).to eq(['web:a'])
          end

          it 'prefers the named group over a process name containing a colon' do
            expect(group).to receive(command).with('job:a').and_return(['web:job:a'])
            expect(other_group).not_to receive(command)
            expect(app.send(command, 'web', 'job:a')).to eq(['web:job:a'])
          end
        end
      end
    end

    describe '#load' do
      it 'starts the server' do
        expect(app).to receive(:start_server)
        app.load
      end

      it 'exits when the server fails to start' do
        error = RuntimeError.new('boom')
        error.set_backtrace(['a.rb:1'])
        allow(app).to receive(:start_server).and_raise(error)
        expect($stderr).to receive(:puts).with('Failed to start bluepill:').ordered
        expect($stderr).to receive(:puts).with('RuntimeError `boom`').ordered
        expect($stderr).to receive(:puts).with(['a.rb:1']).ordered
        expect(app).to receive(:exit).with(5)
        app.load
      end

      it 'reports the message of an error from an anonymous class' do
        error_class = Class.new(StandardError) do
          def message
            'boom'
          end
        end
        allow(app).to receive(:start_server).and_raise(error_class)
        allow($stderr).to receive(:puts)
        expect($stderr).to receive(:puts).with(' `boom`')
        allow(app).to receive(:exit)
        app.load
      end
    end

    describe 'start_server' do
      let(:socket) { double('socket') }
      let(:program_name) { $0 }

      before do
        program_name
        app.groups = {'web' => group}
        allow(app).to receive(:kill_previous_bluepill)
        allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks)
        allow(::Process).to receive(:setpgid)
        allow(Bluepill::Daemonize).to receive(:daemonize)
        allow(group).to receive(:determine_initial_state)
        allow(Bluepill::Socket).to receive(:server).and_return(socket)
        allow(app).to receive(:start_listener)
        allow(app).to receive(:run)
      end

      after { $0 = program_name }

      it 'daemonizes and runs the application' do
        expect(app).to receive(:kill_previous_bluepill).ordered
        expect(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks).ordered
        expect(::Process).to receive(:setpgid).with(0, 0).ordered
        expect(Bluepill::Daemonize).to receive(:daemonize).ordered
        expect(app).to receive(:setup_signal_traps).ordered
        expect(logger).to receive(:reopen).ordered
        expect(group).to receive(:determine_initial_state).ordered
        expect(Bluepill::Socket).to receive(:server).with(base_dir, 'test').ordered
        expect(app).to receive(:start_listener).ordered
        expect(app).to receive(:run).ordered
        app.send(:start_server)
        expect($0).to eq('bluepilld: test')
        expect(File.read(pid_file)).to eq(::Process.pid.to_s)
        expect(app.socket).to eq(socket)
      end

      it 'writes the pid as a string with File.write' do
        expect(File).to receive(:write).with(pid_file, ::Process.pid.to_s).and_call_original
        app.send(:start_server)
      end

      context 'in the foreground' do
        let(:foreground) { true }

        it 'does not daemonize, or trap signals again' do
          expect(Bluepill::Daemonize).not_to receive(:daemonize)
          expect(app).not_to receive(:setup_signal_traps)
          expect(app).to receive(:run)
          app.send(:start_server)
        end
      end

      it 'ignores being unable to become a process group leader' do
        allow(::Process).to receive(:setpgid).and_raise(Errno::EPERM)
        expect(app).to receive(:run)
        app.send(:start_server)
      end
    end

    describe 'run' do
      before { app.groups = {'web' => group, 'db' => other_group} }

      it 'ticks every group each second until terminated' do
        allow(app).to receive(:puts)
        allow(app).to receive(:cleanup)
        ticks = 0
        expect(Bluepill::System).to receive(:reset_data).twice
        expect(group).to receive(:tick).twice
        expect(other_group).to receive(:tick).twice
        expect(app).to receive(:sleep).with(1).twice do
          ticks += 1
          traps['TERM'].call(15) if ticks == 2
        end
        app.send(:run)
      end

      it 'ticks while holding the mutex' do
        locked = false
        allow(app).to receive(:mutex) do |&block|
          locked = true
          block.call
          locked = false
        end
        expect(Bluepill::System).to receive(:reset_data) { expect(locked).to be true }
        expect(group).to receive(:tick) { expect(locked).to be true }
        expect(other_group).to receive(:tick) { expect(locked).to be true }
        expect(app).to receive(:sleep).with(1) { app.instance_variable_set(:@running, false) }
        app.send(:run)
      end
    end

    describe 'cleanup' do
      let(:socket) { double('socket', path: File.join(base_dir, 'test.sock')) }

      before do
        expect(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks)
        expect(Bluepill::System).to receive(:delete_if_exists).with(pid_file)
      end

      it 'deletes the socket and pid file' do
        app.socket = socket
        expect(Bluepill::System).to receive(:delete_if_exists).with(socket.path)
        app.send(:cleanup)
      end

      it 'deletes only the pid file without a socket' do
        app.send(:cleanup)
      end

      it 'ignores a closed socket' do
        allow(socket).to receive(:path).and_raise(IOError)
        app.socket = socket
        app.send(:cleanup)
      end
    end

    describe 'start_listener' do
      let(:client) { double('client', readline: "status:web\n", write: nil, close: nil) }
      let(:server_socket) { double('server socket', accept: client) }
      let(:thread) { double('thread') }
      let(:listener) { [] }

      before do
        app.socket = server_socket
        allow(Thread).to receive(:new) do |&block|
          listener << block
          thread
        end
        allow(app).to receive(:loop).and_yield
      end

      def listen
        app.send(:start_listener)
        listener.last.call
      end

      it 'answers a command with the marshaled response' do
        expect(app).to receive(:loop).and_yield
        allow(client).to receive(:close_on_exec=)
        expect(client).to receive(:close_on_exec=).with(true)
        expect(app).to receive(:status).with('web').and_return(['web:a'])
        expect(client).to receive(:write).with(Marshal.dump(['web:a']))
        expect(client).to receive(:close)
        listen
      end

      it 'ignores whitespace around the command' do
        allow(client).to receive(:readline).and_return(" status:web\n")
        expect(app).to receive(:status).with('web').and_return([])
        listen
      end

      it 'runs the command while holding the mutex' do
        locked = false
        allow(app).to receive(:mutex) do |&block|
          locked = true
          result = block.call
          locked = false
          result
        end
        expect(app).to receive(:status) { expect(locked).to be true }
        listen
      end

      it 'sends a command without a target' do
        allow(client).to receive(:readline).and_return("status:\n")
        expect(app).to receive(:status).with(no_args).and_return([])
        listen
      end

      it 'keeps the colons in a process name' do
        allow(client).to receive(:readline).and_return("status:jobs:job_1:IMPORT\n")
        expect(app).to receive(:status).with('jobs', 'job_1:IMPORT').and_return([])
        listen
      end

      it 'answers with the error raised by a command' do
        error = RuntimeError.new('boom')
        allow(app).to receive(:status).and_raise(error)
        response = nil
        expect(client).to receive(:write) { |data| response = Marshal.load(data) }
        listen
        expect(response).to be_a(RuntimeError)
        expect(response.message).to eq('boom')
      end

      it 'logs errors while handling a client' do
        allow(app).to receive(:status).and_return([])
        error = RuntimeError.new('broken pipe')
        error.set_backtrace(['a.rb:1'])
        allow(client).to receive(:write).and_raise(error)
        expect(logger).to receive(:err).with('Got exception in cmd listener: RuntimeError `broken pipe`').ordered
        expect(logger).to receive(:err).with('a.rb:1').ordered
        expect(client).to receive(:close)
        listen
      end

      it 'logs the message of an error from an anonymous class' do
        error_class = Class.new(StandardError) do
          def message
            'broken pipe'
          end
        end
        allow(app).to receive(:status).and_return([])
        allow(client).to receive(:write).and_raise(error_class)
        expect(logger).to receive(:err).with('Got exception in cmd listener:  `broken pipe`')
        allow(logger).to receive(:err)
        listen
      end

      it 'logs an error without a backtrace' do
        error = RuntimeError.new('broken pipe')
        allow(error).to receive(:backtrace).and_return(nil)
        allow(app).to receive(:status).and_return([])
        allow(client).to receive(:write).and_raise(error)
        expect(logger).to receive(:err).once
        listen
      end

      it 'keeps listening when accepting a client fails' do
        error = Errno::EMFILE.new
        error.set_backtrace(['a.rb:1'])
        allow(server_socket).to receive(:accept).and_raise(error)
        expect(logger).to receive(:err).with("Got exception in cmd listener: Errno::EMFILE `#{error.message}`").ordered
        expect(logger).to receive(:err).with('a.rb:1').ordered
        expect { listen }.not_to raise_error
      end

      it 'ignores an already closed client' do
        allow(app).to receive(:status).and_return([])
        allow(client).to receive(:close).and_raise(IOError)
        expect { listen }.not_to raise_error
      end

      it 'kills the previous listener' do
        app.send(:start_listener)
        expect(thread).to receive(:kill)
        app.send(:start_listener)
      end
    end

    describe 'kill_previous_bluepill' do
      def write_pid
        File.write(pid_file, '1234')
      end

      before { app }

      it 'does nothing without a pid file' do
        expect(Bluepill::System).not_to receive(:pid_alive?)
        app.send(:kill_previous_bluepill)
      end

      it 'does nothing when the previous bluepill is not running' do
        write_pid
        expect(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(false)
        expect(::Process).not_to receive(:kill)
        app.send(:kill_previous_bluepill)
      end

      it 'checks a previous bluepill with pid 1, as in a container' do
        File.write(pid_file, '1')
        expect(Bluepill::System).to receive(:pid_alive?).with(1).and_return(false)
        app.send(:kill_previous_bluepill)
      end

      ['', 'garbage'].each do |contents|
        it "does nothing when the pid file holds #{contents.inspect}" do
          File.write(pid_file, contents)
          expect(Bluepill::System).not_to receive(:pid_alive?)
          expect(::Process).not_to receive(:kill)
          expect(app).not_to receive(:puts)
          expect(app).not_to receive(:exit)
          app.send(:kill_previous_bluepill)
        end
      end

      context 'when the previous bluepill is running' do
        before do
          write_pid
          allow(app).to receive(:puts)
          allow(app).to receive(:sleep)
        end

        it 'interrupts it and waits for it to die' do
          allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true, true, false)
          expect(::Process).to receive(:kill).with(0, 1234).ordered
          expect(app).to receive(:puts).with('Killing previous bluepilld[1234]')
          expect(::Process).to receive(:kill).with(2, 1234).ordered
          expect(app).to receive(:sleep).with(0.5).twice
          expect(app).not_to receive(:exit)
          app.send(:kill_previous_bluepill)
        end

        it 'exits when it does not die' do
          allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true)
          allow(::Process).to receive(:kill)
          expect(app).to receive(:sleep).with(0.5).exactly(10).times
          expect($stderr).to receive(:puts).with("Previous bluepilld[1234] didn't die")
          expect(app).to receive(:exit).with(4)
          app.send(:kill_previous_bluepill)
        end

        it 'carries on when it has just died' do
          allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true)
          allow(::Process).to receive(:kill).and_raise(Errno::ESRCH)
          expect($stderr).to receive(:puts).with('Encountered error trying to kill previous bluepill:').ordered
          expect($stderr).to receive(:puts).with("Errno::ESRCH: #{Errno::ESRCH.new.message}").ordered
          expect(app).not_to receive(:sleep)
          expect(app).not_to receive(:exit)
          app.send(:kill_previous_bluepill)
        end

        it 'exits when it cannot be killed' do
          allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true)
          allow(::Process).to receive(:kill).and_raise(Errno::EPERM)
          allow($stderr).to receive(:puts)
          expect(app).to receive(:exit).with(4)
          app.send(:kill_previous_bluepill)
        end
      end
    end
  end
end
