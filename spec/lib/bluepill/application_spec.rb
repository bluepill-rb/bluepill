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
    subject(:app) { described_class.new('test', options) }

    let(:options) { {} }

    # Don't make the base dir's directories, which for root is /var/run
    before { allow(FileUtils).to receive_messages(mkdir_p: nil, chmod: nil) }

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
          expect(app.base_dir).to eq('/var/run/bluepill')
        ensure
          ENV['HOME'] = home
        end
      end
    end

    context 'without options' do
      subject(:app) { described_class.new('test') }

      before { allow(::Process).to receive(:euid).and_return(0) }

      it 'uses the defaults' do
        expect(app.base_dir).to eq('/var/run/bluepill')
        expect(app).not_to be_foreground
      end
    end

    context 'when option base_dir is specified' do
      let(:options) { {base_dir: '/var/bluepill'} }

      describe '#base_dir' do
        subject { super().base_dir }

        it { is_expected.to eq(options[:base_dir]) }
      end

      it "gives the process journal the base dir and the app's name" do
        app
        expect(Bluepill::ProcessJournal).to have_received(:setup).with('/var/bluepill', 'test')
      end

      it 'derives the pid file and pids dir' do
        expect(app.pid_file).to eq('/var/bluepill/pids/test.pid')
        expect(app.pids_dir).to eq('/var/bluepill/pids/test')
      end

      it 'defaults the kill timeout and foreground mode' do
        expect(app.kill_timeout).to eq(10)
        expect(app).not_to be_foreground
        expect(app.groups).to eq({})
      end

      it 'traps TERM, INT and HUP' do
        app
        expect(traps.keys).to contain_exactly('TERM', 'INT', 'HUP')
      end

      it 'has a mutex' do
        expect(app.mutex { :result }).to eq(:result)
      end

      context 'when foreground is false' do
        let(:options) { {base_dir: '/var/bluepill', foreground: false} }

        it { is_expected.not_to be_foreground }
      end

      it 'logs to the log file with the application name as prefix' do
        expect(app.logger).to eq(logger)
        expect(Bluepill::Logger).to have_received(:new).with(log_file: nil, log_level: nil, stdout: false)
        expect(logger).to have_received(:prefix_with).with('test')
        expect(Bluepill::ProcessJournal).to have_received(:logger=).with(logger)
      end

      context 'with other options' do
        let(:options) { {base_dir: '/var/bluepill', foreground: true, log_file: 'log', log_level: :info, kill_timeout: 3} }

        it 'uses them' do
          expect(app.kill_timeout).to eq(3)
          expect(app.log_file).to eq('log')
          expect(app).to be_foreground
          expect(Bluepill::Logger).to have_received(:new).with(log_file: 'log', log_level: :info, stdout: true)
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

      context 'with a base_dir option' do
        let(:options) { {base_dir: '/var/bluepill'} }

        describe '#base_dir' do
          subject { super().base_dir }

          it { is_expected.to eq(options[:base_dir]) }
        end
      end
    end
  end
  def exit_with(status)
    raise_error(an_instance_of(SystemExit).and(having_attributes(status: status)))
  end

  describe '#initialize without permission to write its files' do
    subject(:app) { described_class.new('test', base_dir: '/var/bluepill', log_file: '/var/log/bluepill.log') }

    def startup_failure(message)
      exit_with(5).and output(
        "Failed to start bluepill: #{message}\n" \
        'The user running bluepill must be able to write to its log_file and base_dir. ' \
        "The uid and gid in the config only apply to the processes it monitors.\n"
      ).to_stderr
    end

    it 'exits with a clear message when it cannot open the log file' do
      allow(Bluepill::Logger).to receive(:new).and_raise(Errno::EACCES, '/var/log/bluepill.log')
      expect { app }.to startup_failure('Permission denied - /var/log/bluepill.log')
    end

    it 'exits with a clear message when it cannot create the pids dir' do
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, '/var/bluepill/pids/test')
      expect { app }.to startup_failure('Permission denied - /var/bluepill/pids/test')
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
          allow(app).to receive(:cleanup)
          expect { traps[signal].call(Signal.list.fetch(signal)) }.to output("Terminating...\n").to_stdout
          expect(app).to have_received(:cleanup)
          expect(app.instance_variable_get(:@running)).to be false
        end
      end

      it 'reopens the log on HUP' do
        traps['HUP'].call
        expect(logger).to have_received(:reopen)
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
      let(:process) { instance_double(Bluepill::Process, :app_name= => nil, :group_name= => nil) }

      it 'adds the process to a new group named after the group name' do
        group_logger = instance_double(Bluepill::Logger)
        allow(logger).to receive(:prefix_with).with('web').and_return(group_logger)
        allow(Bluepill::Group).to receive(:new).with('web', logger: group_logger).and_return(group)
        allow(group).to receive(:add_process)
        app.add_process(process, :web)
        expect(app.groups).to eq('web' => group)
        expect(group).to have_received(:add_process).with(process)
      end

      it 'adds processes without a group to the nil group' do
        allow(Bluepill::Group).to receive(:new).with(nil, logger: logger).and_return(group)
        allow(group).to receive(:add_process)
        app.add_process(process)
        app.add_process(process)
        expect(app.groups).to eq(nil => group)
        expect(Bluepill::Group).to have_received(:new).once
        expect(group).to have_received(:add_process).with(process).twice
      end

      it "tells the process its app's and group's names, for notify_command" do
        allow(Bluepill::Group).to receive(:new).and_return(group)
        allow(group).to receive(:add_process)
        app.add_process(process, :web)
        expect(process).to have_received(:app_name=).with('test')
        expect(process).to have_received(:group_name=).with('web')
      end
    end

    describe 'process commands' do
      before { app.groups = {'web' => group, 'db' => other_group} }

      described_class::PROCESS_COMMANDS.each do |command|
        describe "##{command}" do
          it 'is sent to every group without arguments' do
            allow(group).to receive(command).with(no_args).and_return(['web:a'])
            allow(other_group).to receive(command).with(no_args).and_return(['db:b'])
            expect(app.send(command)).to eq(['web:a', 'db:b'])
          end

          it 'is sent to the named group' do
            allow(group).to receive(command).with('a').and_return(['web:a'])
            expect(app.send(command, 'web', 'a')).to eq(['web:a'])
          end

          it 'is sent to every group for a process name' do
            allow(group).to receive(command).with('a').and_return(['web:a'])
            allow(other_group).to receive(command).with('a').and_return(['db:a'])
            expect(app.send(command, 'a')).to eq(['web:a', 'db:a'])
          end

          it 'is sent to every group for a process name containing a colon' do
            allow(group).to receive(command).with('job:a').and_return(['web:job:a'])
            allow(other_group).to receive(command).with('job:a').and_return(['db:job:a'])
            expect(app.send(command, 'job', 'a')).to eq(['web:job:a', 'db:job:a'])
          end

          it 'is sent to every group for a process name without a group' do
            allow(group).to receive(command).with('a').and_return(['web:a'])
            allow(other_group).to receive(command).with('a').and_return(['db:a'])
            expect(app.send(command, nil, 'a')).to eq(['web:a', 'db:a'])
          end

          it 'prefers the named group over a process name containing a colon' do
            allow(group).to receive(command).with('job:a').and_return(['web:job:a'])
            allow(other_group).to receive(command)
            expect(app.send(command, 'web', 'job:a')).to eq(['web:job:a'])
            expect(other_group).not_to have_received(command)
          end
        end
      end
    end

    describe '#load' do
      it 'starts the server' do
        allow(app).to receive(:start_server)
        app.load
        expect(app).to have_received(:start_server)
      end

      it 'exits when the server fails to start' do
        error = RuntimeError.new('boom')
        error.set_backtrace(['a.rb:1'])
        allow(app).to receive(:start_server).and_raise(error)
        expect { app.load }.to exit_with(5).and output("Failed to start bluepill:\nRuntimeError `boom`\na.rb:1\n").to_stderr
      end

      it 'reports the message of an error from an anonymous class' do
        error_class = Class.new(StandardError) do
          def message
            'boom'
          end
        end
        allow(app).to receive(:start_server).and_raise(error_class)
        expect { app.load }.to exit_with(5).and output(/^ `boom`$/).to_stderr
      end
    end

    describe 'start_server' do
      let(:socket) { instance_double(UNIXServer) }
      let(:program_name) { $0 }

      before do
        program_name
        app.groups = {'web' => group}
        allow(app).to receive(:kill_previous_bluepill)
        allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks)
        allow(::Process).to receive(:setpgid)
        allow(Bluepill::Daemonize).to receive(:daemonize)
        allow(app).to receive(:setup_signal_traps)
        allow(group).to receive(:determine_initial_state)
        allow(Bluepill::Socket).to receive(:server).and_return(socket)
        allow(app).to receive(:start_listener)
        allow(app).to receive(:run)
      end

      after { $0 = program_name }

      it 'daemonizes and runs the application' do
        calls = []
        [
          [app, :kill_previous_bluepill], [Bluepill::ProcessJournal, :clear_all_atomic_fs_locks],
          [::Process, :setpgid], [Bluepill::Daemonize, :daemonize], [app, :setup_signal_traps],
          [logger, :reopen], [group, :determine_initial_state], [app, :start_listener], [app, :run],
        ].each do |object, method|
          allow(object).to receive(method) { |*args| calls << [method, *args] }
        end
        allow(Bluepill::Socket).to receive(:server) do |*args|
          calls << [:server, *args]
          socket
        end
        app.send(:start_server)
        expect(calls).to eq(
          [
            [:kill_previous_bluepill], [:clear_all_atomic_fs_locks], [:setpgid, 0, 0], [:daemonize],
            [:setup_signal_traps], [:reopen], [:determine_initial_state], [:server, base_dir, 'test'],
            [:start_listener], [:run],
          ]
        )
        expect($0).to eq('bluepilld: test')
        expect(File.read(pid_file)).to eq(::Process.pid.to_s)
        expect(app.socket).to eq(socket)
      end

      it 'writes the pid as a string with File.write' do
        allow(File).to receive(:write).and_call_original
        app.send(:start_server)
        expect(File).to have_received(:write).with(pid_file, ::Process.pid.to_s)
      end

      context 'when in the foreground' do
        let(:foreground) { true }

        it 'does not daemonize, or trap signals again' do
          app.send(:start_server)
          expect(Bluepill::Daemonize).not_to have_received(:daemonize)
          expect(app).not_to have_received(:setup_signal_traps)
          expect(app).to have_received(:run)
        end
      end

      it 'ignores being unable to become a process group leader' do
        allow(::Process).to receive(:setpgid).and_raise(Errno::EPERM)
        app.send(:start_server)
        expect(app).to have_received(:run)
      end
    end

    describe 'run' do
      before { app.groups = {'web' => group, 'db' => other_group} }

      it 'ticks every group each second until terminated' do
        allow(app).to receive(:puts)
        allow(app).to receive(:cleanup)
        calls = []
        allow(Bluepill::System).to receive(:reset_data) { calls << :reset_data }
        allow(group).to receive(:tick) { calls << :web }
        allow(other_group).to receive(:tick) { calls << :db }
        allow(app).to receive(:sleep).with(1) do
          calls << :sleep
          traps['TERM'].call(15) if calls.count(:sleep) == 2
        end
        app.send(:run)
        expect(calls).to eq([:reset_data, :web, :db, :sleep, :reset_data, :web, :db, :sleep])
      end

      it 'ticks while holding the mutex' do
        locked = false
        allow(app).to receive(:mutex) do |&block|
          locked = true
          block.call
          locked = false
        end
        calls = []
        allow(Bluepill::System).to receive(:reset_data) { calls << [:reset_data, locked] }
        allow(group).to receive(:tick) { calls << [:web, locked] }
        allow(other_group).to receive(:tick) { calls << [:db, locked] }
        allow(app).to receive(:sleep).with(1) do
          calls << [:sleep, locked]
          app.instance_variable_set(:@running, false)
        end
        app.send(:run)
        expect(calls).to eq([[:reset_data, true], [:web, true], [:db, true], [:sleep, false]])
      end
    end

    describe 'cleanup' do
      let(:socket) { instance_double(UNIXServer, path: File.join(base_dir, 'test.sock')) }

      before do
        allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks)
        allow(Bluepill::System).to receive(:delete_if_exists)
      end

      it 'clears the journal locks' do
        app.send(:cleanup)
        expect(Bluepill::ProcessJournal).to have_received(:clear_all_atomic_fs_locks)
      end

      it 'deletes the pid file' do
        app.send(:cleanup)
        expect(Bluepill::System).to have_received(:delete_if_exists).with(pid_file)
      end

      it 'deletes the socket' do
        app.socket = socket
        app.send(:cleanup)
        expect(Bluepill::System).to have_received(:delete_if_exists).with(socket.path)
      end

      it 'deletes only the pid file without a socket' do
        app.send(:cleanup)
        expect(Bluepill::System).to have_received(:delete_if_exists).once
      end

      it 'ignores a closed socket' do
        allow(socket).to receive(:path).and_raise(IOError)
        app.socket = socket
        app.send(:cleanup)
        expect(Bluepill::System).to have_received(:delete_if_exists).once
      end
    end

    describe 'start_listener' do
      let(:client) { instance_double(UNIXSocket, readline: "status:web\n", write: nil, close: nil) }
      let(:server_socket) { instance_double(UNIXServer, accept: client) }
      let(:thread) { instance_double(Thread) }
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
        allow(client).to receive(:close_on_exec=)
        allow(app).to receive(:status).with('web').and_return(['web:a'])
        listen
        expect(app).to have_received(:loop)
        expect(client).to have_received(:close_on_exec=).with(true)
        expect(client).to have_received(:write).with(Marshal.dump(['web:a']))
        expect(client).to have_received(:close)
      end

      it 'ignores whitespace around the command' do
        allow(client).to receive(:readline).and_return(" status:web\n")
        allow(app).to receive(:status).and_return([])
        listen
        expect(app).to have_received(:status).with('web')
      end

      it 'runs the command while holding the mutex' do
        locked = false
        allow(app).to receive(:mutex) do |&block|
          locked = true
          result = block.call
          locked = false
          result
        end
        locked_during_status = nil
        allow(app).to receive(:status) { locked_during_status = locked }
        listen
        expect(locked_during_status).to be true
      end

      it 'sends a command without a target' do
        allow(client).to receive(:readline).and_return("status:\n")
        allow(app).to receive(:status).and_return([])
        listen
        expect(app).to have_received(:status).with(no_args)
      end

      it 'keeps the colons in a process name' do
        allow(client).to receive(:readline).and_return("status:jobs:job_1:IMPORT\n")
        allow(app).to receive(:status).and_return([])
        listen
        expect(app).to have_received(:status).with('jobs', 'job_1:IMPORT')
      end

      it 'answers with the error raised by a command' do
        error = RuntimeError.new('boom')
        allow(app).to receive(:status).and_raise(error)
        response = nil
        allow(client).to receive(:write) { |data| response = Marshal.load(data) }
        listen
        expect(response).to be_a(RuntimeError)
        expect(response.message).to eq('boom')
      end

      it 'logs errors while handling a client' do
        allow(app).to receive(:status).and_return([])
        error = RuntimeError.new('broken pipe')
        error.set_backtrace(['a.rb:1'])
        allow(client).to receive(:write).and_raise(error)
        listen
        expect(logger).to have_received(:err).with('Got exception in cmd listener: RuntimeError `broken pipe`').ordered
        expect(logger).to have_received(:err).with('a.rb:1').ordered
        expect(client).to have_received(:close)
      end

      it 'logs the message of an error from an anonymous class' do
        error_class = Class.new(StandardError) do
          def message
            'broken pipe'
          end
        end
        allow(app).to receive(:status).and_return([])
        allow(client).to receive(:write).and_raise(error_class)
        listen
        expect(logger).to have_received(:err).with('Got exception in cmd listener:  `broken pipe`')
      end

      it 'logs an error without a backtrace' do
        error = RuntimeError.new('broken pipe')
        allow(error).to receive(:backtrace).and_return(nil)
        allow(app).to receive(:status).and_return([])
        allow(client).to receive(:write).and_raise(error)
        listen
        expect(logger).to have_received(:err).once
      end

      it 'keeps listening when accepting a client fails' do
        error = Errno::EMFILE.new
        error.set_backtrace(['a.rb:1'])
        allow(server_socket).to receive(:accept).and_raise(error)
        expect { listen }.not_to raise_error
        expect(logger).to have_received(:err).with("Got exception in cmd listener: Errno::EMFILE `#{error.message}`").ordered
        expect(logger).to have_received(:err).with('a.rb:1').ordered
      end

      it 'ignores an already closed client' do
        allow(app).to receive(:status).and_return([])
        allow(client).to receive(:close).and_raise(IOError)
        expect { listen }.not_to raise_error
      end

      it 'kills the previous listener' do
        allow(thread).to receive(:kill)
        app.send(:start_listener)
        app.send(:start_listener)
        expect(thread).to have_received(:kill).once
      end
    end

    describe 'kill_previous_bluepill' do
      def write_pid
        File.write(pid_file, '1234')
      end

      def kill_previous_bluepill
        app.send(:kill_previous_bluepill)
      end

      before do
        app
        allow(Bluepill::System).to receive(:pid_alive?).and_return(false)
        allow(::Process).to receive(:kill)
      end

      it 'does nothing without a pid file' do
        kill_previous_bluepill
        expect(Bluepill::System).not_to have_received(:pid_alive?)
      end

      it 'does nothing when the previous bluepill is not running' do
        write_pid
        kill_previous_bluepill
        expect(Bluepill::System).to have_received(:pid_alive?).with(1234)
        expect(::Process).not_to have_received(:kill)
      end

      it 'checks a previous bluepill with pid 1, as in a container' do
        File.write(pid_file, '1')
        kill_previous_bluepill
        expect(Bluepill::System).to have_received(:pid_alive?).with(1)
      end

      ['', 'garbage'].each do |contents|
        it "does nothing when the pid file holds #{contents.inspect}" do
          File.write(pid_file, contents)
          expect { kill_previous_bluepill }.not_to output.to_stdout
          expect(Bluepill::System).not_to have_received(:pid_alive?)
          expect(::Process).not_to have_received(:kill)
        end
      end

      context 'when the previous bluepill is running' do
        before do
          write_pid
          allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true)
          allow(app).to receive(:puts)
          allow(app).to receive(:sleep)
        end

        it 'interrupts it and waits for it to die' do
          allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true, true, false)
          kill_previous_bluepill
          expect(::Process).to have_received(:kill).with(0, 1234).ordered
          expect(::Process).to have_received(:kill).with(2, 1234).ordered
          expect(app).to have_received(:puts).with('Killing previous bluepilld[1234]')
          expect(app).to have_received(:sleep).with(0.5).twice
        end

        it 'exits when it does not die' do
          expect { kill_previous_bluepill }.to exit_with(4).and output("Previous bluepilld[1234] didn't die\n").to_stderr
          expect(app).to have_received(:sleep).with(0.5).exactly(10).times
        end

        it 'carries on when it has just died' do
          allow(::Process).to receive(:kill).and_raise(Errno::ESRCH)
          expect { kill_previous_bluepill }.to output(
            "Encountered error trying to kill previous bluepill:\nErrno::ESRCH: #{Errno::ESRCH.new.message}\n"
          ).to_stderr
          expect(app).not_to have_received(:sleep)
        end

        it 'exits when it cannot be killed' do
          allow(::Process).to receive(:kill).and_raise(Errno::EPERM)
          expect { kill_previous_bluepill }.to exit_with(4).and output(
            "Encountered error trying to kill previous bluepill:\nErrno::EPERM: #{Errno::EPERM.new.message}\n"
          ).to_stderr
        end
      end
    end
  end
end
