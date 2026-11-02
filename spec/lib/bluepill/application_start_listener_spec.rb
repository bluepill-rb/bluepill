require 'tmpdir'

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger, debug: nil, err: nil, reopen: nil) }
  let(:traps) { {} }
  let(:base_dir) { Dir.mktmpdir }
  let(:foreground) { false }
  let(:app) { described_class.new('test', base_dir: base_dir, foreground: foreground) }
  let(:pids_dir) { File.join(base_dir, 'pids', 'test') }
  let(:pid_file) { File.join(base_dir, 'pids', 'test.pid') }
  let(:group) { instance_double(Bluepill::Group) }
  let(:other_group) { instance_double(Bluepill::Group) }

  before do
    allow(logger).to receive(:prefix_with).and_return(logger)
    allow(Bluepill::Logger).to receive(:new).and_return(logger)
    allow(Bluepill::ProcessJournal).to receive(:setup)
    allow(Bluepill::ProcessJournal).to receive(:logger=)
    allow(Signal).to receive(:trap) { |signal, &block| traps[signal] = block }
  end

  after { FileUtils.remove_entry(base_dir) }

  # An error whose class has no name
  def anonymous_error(message)
    Class.new(StandardError) { define_method(:message) { message } }
  end

  def mutex_locked?
    app.instance_variable_get(:@mutex).locked?
  end

  describe 'start_listener' do
    let(:client) { instance_double(UNIXSocket, readline: "status:web\n", write: nil, close: nil) }
    let(:server_socket) { instance_double(UNIXServer, accept: client) }
    let(:logged) { [] }

    before do
      app.socket = server_socket
      # The listener's thread is its block, which listen calls
      allow(Thread).to receive(:new) { |&block| block }
      allow(app).to receive(:loop).and_yield
      allow(app).to receive(:status).and_return([])
      allow(logger).to receive(:err) { |line| logged << line }
    end

    def listen
      app.send(:start_listener).call
    end

    context 'with a command' do
      before do
        allow(client).to receive(:close_on_exec=)
        allow(app).to receive(:status).with('web').and_return(['web:a'])
        listen
      end

      it 'listens in a loop' do
        expect(app).to have_received(:loop)
      end

      it 'keeps the client from leaking into processes it starts' do
        expect(client).to have_received(:close_on_exec=).with(true)
      end

      it 'answers with the marshaled response' do
        expect(client).to have_received(:write).with(Marshal.dump(['web:a']))
      end

      it 'closes the client' do
        expect(client).to have_received(:close)
      end
    end

    it 'ignores whitespace around the command' do
      allow(client).to receive(:readline).and_return(" status:web\n")
      listen
      expect(app).to have_received(:status).with('web')
    end

    it 'runs the command while holding the mutex' do
      allow(app).to receive(:status) { mutex_locked? }
      listen
      expect(client).to have_received(:write).with(Marshal.dump(true))
    end

    it 'sends a command without a target' do
      allow(client).to receive(:readline).and_return("status:\n")
      listen
      expect(app).to have_received(:status).with(no_args)
    end

    it 'keeps the colons in a process name' do
      allow(client).to receive(:readline).and_return("status:jobs:job_1:IMPORT\n")
      listen
      expect(app).to have_received(:status).with('jobs', 'job_1:IMPORT')
    end

    it 'answers with the error raised by a command' do
      error = RuntimeError.new('boom')
      allow(app).to receive(:status).and_raise(error)
      listen
      expect(client).to have_received(:write).with(Marshal.dump(error))
    end

    context 'when handling a client fails' do
      before do
        error = RuntimeError.new('broken pipe')
        error.set_backtrace(['a.rb:1'])
        allow(client).to receive(:write).and_raise(error)
        listen
      end

      it 'logs the error and its backtrace' do
        expect(logged).to eq(['Got exception in cmd listener: RuntimeError `broken pipe`', 'a.rb:1'])
      end

      it 'closes the client' do
        expect(client).to have_received(:close)
      end
    end

    it 'logs the message of an error from an anonymous class' do
      allow(client).to receive(:write).and_raise(anonymous_error('broken pipe'))
      listen
      expect(logged.first).to eq('Got exception in cmd listener:  `broken pipe`')
    end

    it 'logs an error without a backtrace' do
      error = RuntimeError.new('broken pipe')
      allow(error).to receive(:backtrace).and_return(nil)
      allow(client).to receive(:write).and_raise(error)
      listen
      expect(logged).to eq(['Got exception in cmd listener: RuntimeError `broken pipe`'])
    end

    context 'when accepting a client fails' do
      let(:error) do
        Errno::EMFILE.new.tap { |e| e.set_backtrace(['a.rb:1']) }
      end

      before { allow(server_socket).to receive(:accept).and_raise(error) }

      it 'keeps listening' do
        expect { listen }.not_to raise_error
      end

      it 'logs the error and its backtrace' do
        listen
        expect(logged).to eq(["Got exception in cmd listener: Errno::EMFILE `#{error.message}`", 'a.rb:1'])
      end
    end

    it 'ignores an already closed client' do
      allow(client).to receive(:close).and_raise(IOError)
      expect { listen }.not_to raise_error
    end

    it 'kills the previous listener' do
      thread = instance_double(Thread, kill: nil)
      allow(Thread).to receive(:new).and_return(thread)
      app.send(:start_listener)
      app.send(:start_listener)
      expect(thread).to have_received(:kill).once
    end
  end
end
