describe Bluepill::Daemonize do
  # Stands in for Process.exit!, which would end the spec run
  let(:exited) { Class.new(StandardError) }

  let(:rd) { double('rd', close: nil, read: '') }
  let(:wr) { double('wr', close: nil, write: nil) }

  before do
    allow(IO).to receive(:pipe).and_return([rd, wr])
    allow(Process).to receive(:exit!).and_raise(exited)
    allow(described_class).to receive(:exit!).and_raise('exit! must be called on Process')
    allow(Process).to receive(:waitpid)
    allow(Process).to receive(:setsid).and_return(5)
    allow(Signal).to receive(:trap)
  end

  describe '.safefork' do
    it 'returns the child pid in the parent' do
      allow(described_class).to receive(:fork).and_return(123)
      expect(described_class.safefork).to eq(123)
    end

    it 'returns nil in the child' do
      allow(described_class).to receive(:fork).and_return(nil)
      expect(described_class.safefork).to be_nil
    end

    it 'retries every 5 seconds while the system is out of processes' do
      calls = 0
      allow(described_class).to receive(:fork) do
        calls += 1
        raise Errno::EWOULDBLOCK if calls < 3

        7
      end
      allow(described_class).to receive(:sleep)
      expect(described_class.safefork).to eq(7)
      expect(described_class).to have_received(:sleep).with(5).twice
    end
  end

  describe '.call_as_daemon' do
    let(:block) { double('block', call: nil) }

    it 'returns the pid the daemon reports, once the process between exits' do
      allow(described_class).to receive(:safefork).and_return(42)
      allow(rd).to receive(:read).and_return('99')
      expect(described_class.call_as_daemon(block, 'name')).to eq(99)
      expect(wr).to have_received(:close).ordered
      expect(rd).to have_received(:close).ordered
      expect(Process).to have_received(:waitpid).with(42)
      expect(block).not_to have_received(:call)
    end

    it 'returns 0 when the daemon never reports its pid' do
      allow(described_class).to receive(:safefork).and_return(42)
      expect(described_class.call_as_daemon(block)).to eq(0)
    end

    context 'when in a forked copy of the bluepill daemon' do
      before do
        # https://github.com/bluepill-rb/bluepill/issues/1: exit would run
        # the real daemon's ensure blocks in the copy
        allow(described_class).to receive(:exit).and_raise('a forked copy must exit with Process.exit!, not exit')
        allow(described_class).to receive(:become_daemon)
      end

      it 'exits the process between with exit!, after starting a session' do
        allow(described_class).to receive(:safefork).and_return(nil, 77)
        expect { described_class.call_as_daemon(block, 'name') }.to raise_error(exited)
        expect(rd).to have_received(:close)
        expect(Process).to have_received(:setsid)
        expect(wr).to have_received(:close)
        expect(Process).to have_received(:exit!).with(true)
        expect(wr).not_to have_received(:write)
        expect(block).not_to have_received(:call)
      end

      it 'reports its pid, runs the block as a daemon, and exits with exit!' do
        allow(described_class).to receive(:safefork).and_return(nil, nil)
        expect { described_class.call_as_daemon(block, 'name') }.to raise_error(exited)
        expect(wr).to have_received(:write).with(Process.pid).ordered
        expect(wr).to have_received(:close).ordered
        expect(described_class).to have_received(:become_daemon).with('name').ordered
        expect(block).to have_received(:call).ordered
        expect(Process).to have_received(:exit!).with(true).ordered
      end

      it 'keeps its process title without a name' do
        allow(described_class).to receive(:safefork).and_return(nil, nil)
        expect { described_class.call_as_daemon(block) }.to raise_error(exited)
        expect(described_class).to have_received(:become_daemon).with(nil)
      end
    end
  end

  describe '.daemonize' do
    before do
      allow(described_class).to receive(:become_daemon)
    end

    it 'exits the process that called it, so the command returns' do
      allow(described_class).to receive(:safefork).and_return(1)
      allow(described_class).to receive(:exit).and_raise(SystemExit)
      expect { described_class.daemonize }.to raise_error(SystemExit)
      expect(described_class).to have_received(:exit).with(no_args)
      expect(Process).not_to have_received(:setsid)
    end

    it 'exits the session leader with exit!' do
      allow(described_class).to receive(:safefork).and_return(nil, 2)
      expect { described_class.daemonize }.to raise_error(exited)
      expect(Process).to have_received(:setsid).ordered
      expect(Process).to have_received(:exit!).with(true).ordered
      expect(described_class).not_to have_received(:become_daemon)
    end

    it 'becomes the daemon, and returns its session id' do
      allow(described_class).to receive(:safefork).and_return(nil, nil)
      expect(described_class.daemonize).to eq(5)
      expect(described_class).to have_received(:become_daemon).with(no_args)
    end
  end

  describe '.detach' do
    it 'starts a session, ignores hangups, and returns the session id' do
      expect(described_class.detach).to eq(5)
      expect(Process).to have_received(:setsid).ordered
      expect(Signal).to have_received(:trap).with('SIGHUP', 'IGNORE').ordered
    end

    it 'raises when there is no session to start' do
      allow(Process).to receive(:setsid).and_return(nil)
      expect { described_class.detach }.to raise_error(Bluepill::Daemonize::Error, 'cannot detach from controlling terminal')
      expect(Signal).not_to have_received(:trap)
    end
  end

  describe '.become_daemon' do
    around do |example|
      title = $0
      example.run
      $0 = title
    end

    before do
      allow(Dir).to receive(:chdir)
      allow(described_class).to receive(:close_io)
      allow(described_class).to receive(:redirect_io)
      allow(described_class).to receive(:srand)
    end

    it 'sets the title, leaves its directory, closes and redirects io, and reseeds' do
      described_class.become_daemon('my daemon')
      expect($0).to eq('my daemon')
      expect(Dir).to have_received(:chdir).with('/').ordered
      expect(described_class).to have_received(:close_io).with(no_args).ordered
      expect(described_class).to have_received(:redirect_io).with(no_args).ordered
      expect(described_class).to have_received(:srand).with(no_args).ordered
    end

    it 'keeps the title without a name' do
      title = $0
      described_class.become_daemon
      expect($0).to eq(title)
    end
  end

  describe '.close_io' do
    let(:open_io) { double('open', closed?: false, close: nil) }
    let(:closed_io) { double('closed', closed?: true) }
    let(:failing_io) { double('failing', closed?: false) }
    let(:first_fd) { double('fd 3', close: nil) }
    let(:last_fd) { double('last fd', close: nil) }

    before do
      allow(failing_io).to receive(:close).and_raise(IOError)
      ios = [STDIN, open_io, STDOUT, closed_io, STDERR, failing_io]
      allow(ObjectSpace).to receive(:each_object).with(IO) { |&block| ios.each(&block) }
      allow(IO).to receive(:for_fd).and_raise(Errno::EBADF)
      allow(IO).to receive(:for_fd).with(3).and_return(first_fd)
      allow(IO).to receive(:for_fd).with(Bluepill::Daemonize::MAX_FD).and_return(last_fd)
      allow(STDIN).to receive(:close)
      allow(STDOUT).to receive(:close)
      allow(STDERR).to receive(:close)
    end

    it 'closes every open IO but the standard streams' do
      described_class.close_io
      expect(open_io).to have_received(:close)
      expect(failing_io).to have_received(:close)
      expect(STDIN).not_to have_received(:close)
      expect(STDOUT).not_to have_received(:close)
      expect(STDERR).not_to have_received(:close)
    end

    it 'closes every file descriptor from 3 up' do
      described_class.close_io
      expect(IO).not_to have_received(:for_fd).with(2)
      expect(first_fd).to have_received(:close)
      expect(last_fd).to have_received(:close)
      expect(IO).not_to have_received(:for_fd).with(Bluepill::Daemonize::MAX_FD + 1)
    end

    it 'goes on past a file descriptor that will not close' do
      allow(first_fd).to receive(:close).and_raise(IOError)
      described_class.close_io
      expect(last_fd).to have_received(:close)
    end
  end

  describe '.redirect_io' do
    before do
      allow(STDIN).to receive(:reopen)
      allow(STDOUT).to receive(:reopen)
      allow(STDERR).to receive(:reopen)
      allow(STDERR).to receive(:sync=)
    end

    it 'points the standard streams at /dev/null' do
      described_class.redirect_io
      expect(STDIN).to have_received(:reopen).with(File::NULL)
      expect(STDOUT).to have_received(:reopen).with(File::NULL)
      expect(STDERR).to have_received(:reopen).with(STDOUT)
      expect(STDERR).to have_received(:sync=).with(true)
    end

    it 'goes on past a stream that will not reopen' do
      allow(STDIN).to receive(:reopen).and_raise(Errno::ENOENT)
      allow(STDERR).to receive(:reopen).and_raise(IOError)
      described_class.redirect_io
      expect(STDOUT).to have_received(:reopen).with(File::NULL)
      expect(STDERR).to have_received(:sync=).with(true)
    end
  end
end
