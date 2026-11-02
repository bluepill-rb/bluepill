require 'tmpdir'

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger) }
  let(:base_dir) { Dir.mktmpdir }
  let(:app) { described_class.new('test', base_dir: base_dir) }

  before do
    allow(logger).to receive(:prefix_with).and_return(logger)
    allow(Bluepill::Logger).to receive(:new).and_return(logger)
    allow(Bluepill::ProcessJournal).to receive(:setup)
    allow(Bluepill::ProcessJournal).to receive(:logger=)
    # Don't trap the specs' own signals
    allow(Signal).to receive(:trap)
  end

  after { FileUtils.remove_entry(base_dir) }

  def exit_with(status)
    raise_error(an_instance_of(SystemExit).and(having_attributes(status: status)))
  end

  # An error whose class has no name
  def anonymous_error(message)
    Class.new(StandardError) { define_method(:message) { message } }
  end

  def pid_file
    File.join(base_dir, 'pids', 'test.pid')
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
      allow(app).to receive(:start_server).and_raise(anonymous_error('boom'))
      expect { app.load }.to exit_with(5).and output(/^ `boom`$/).to_stderr
    end
  end

  describe 'start_server' do
    let(:group) { instance_double(Bluepill::Group) }
    let(:calls) { [] }

    around do |example|
      program_name = $0
      begin
        example.run
      ensure
        $0 = program_name
      end
    end

    before do
      app.groups = {'web' => group}
      [
        [app, :kill_previous_bluepill], [Bluepill::ProcessJournal, :clear_all_atomic_fs_locks],
        [::Process, :setpgid], [Bluepill::Daemonize, :daemonize], [app, :setup_signal_traps],
        [logger, :reopen], [group, :determine_initial_state], [app, :start_listener], [app, :run]
      ].each do |object, method|
        allow(object).to receive(method) { |*args| calls << [method, *args] }
      end
      allow(Bluepill::Socket).to receive(:server) do |*args|
        calls << [:server, *args]
        instance_double(UNIXServer)
      end
    end

    def startup_calls
      [
        [:kill_previous_bluepill], [:clear_all_atomic_fs_locks], [:setpgid, 0, 0], [:daemonize],
        [:setup_signal_traps], [:reopen], [:determine_initial_state], [:server, base_dir, 'test'],
        [:start_listener], [:run]
      ]
    end

    it 'daemonizes and runs the application' do
      app.send(:start_server)
      expect(calls).to eq(startup_calls)
    end

    it 'names its process after the application' do
      app.send(:start_server)
      expect($0).to eq('bluepilld: test')
    end

    it 'writes its pid file' do
      app.send(:start_server)
      expect(File.read(pid_file)).to eq(::Process.pid.to_s)
    end

    it 'keeps the socket' do
      socket = instance_double(UNIXServer)
      allow(Bluepill::Socket).to receive(:server).and_return(socket)
      app.send(:start_server)
      expect(app.socket).to eq(socket)
    end

    it 'writes the pid as a string with File.write' do
      allow(File).to receive(:write).and_call_original
      app.send(:start_server)
      expect(File).to have_received(:write).with(pid_file, ::Process.pid.to_s)
    end

    context 'when in the foreground' do
      let(:app) { described_class.new('test', base_dir: base_dir, foreground: true) }

      it 'does not daemonize, or trap signals again' do
        app.send(:start_server)
        expect(calls).to eq(startup_calls - [[:daemonize], [:setup_signal_traps]])
      end
    end

    it 'ignores being unable to become a process group leader' do
      allow(::Process).to receive(:setpgid).and_raise(Errno::EPERM)
      app.send(:start_server)
      expect(app).to have_received(:run)
    end
  end
end
