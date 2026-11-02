describe Bluepill::Daemonize do
  # Stands in for Process.exit!, which would end the spec run
  let(:exited) { Class.new(StandardError) }
  # What the daemon does to the system, in order
  let(:events) { [] }

  before do
    allow(Process).to(receive(:exit!)) do |*args|
      events << [:exit!, *args]
      raise exited
    end
    allow(described_class).to receive(:exit!).and_raise('exit! must be called on Process')
    allow(Process).to(receive(:waitpid)) { |pid| events << [:waitpid, pid] }
    allow(Process).to(receive(:setsid)) do
      events << [:setsid]
      5
    end
    allow(Signal).to(receive(:trap)) { |*args| events << [:trap, *args] }
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

    context 'when the system is out of processes at first' do
      before do
        calls = 0
        allow(described_class).to receive(:fork) do
          calls += 1
          raise Errno::EWOULDBLOCK if calls < 3

          7
        end
        allow(described_class).to receive(:sleep)
      end

      it 'returns the child pid once a fork works' do
        expect(described_class.safefork).to eq(7)
      end

      it 'waits 5 seconds before each retry' do
        described_class.safefork
        expect(described_class).to have_received(:sleep).with(5).twice
      end
    end
  end

  describe '.call_as_daemon' do
    let(:rd) { instance_double(IO, read: '') }
    let(:wr) { instance_double(IO) }
    let(:block) { instance_double(Proc) }

    before do
      allow(IO).to receive(:pipe).and_return([rd, wr])
      allow(rd).to(receive(:close)) { events << [:close, :rd] }
      allow(wr).to(receive(:close)) { events << [:close, :wr] }
      allow(wr).to(receive(:write)) { |data| events << [:write, data] }
      allow(block).to(receive(:call)) { events << [:call] }
    end

    context 'when in the process that called it' do
      before do
        allow(described_class).to receive(:safefork).and_return(42)
        allow(rd).to receive(:read).and_return('99')
      end

      it 'returns the pid the daemon reports, once the process between exits' do
        expect(described_class.call_as_daemon(block, 'name')).to eq(99)
      end

      it 'closes the pipe and waits for the process between, without running the block' do
        described_class.call_as_daemon(block, 'name')
        expect(events).to eq([[:close, :wr], [:close, :rd], [:waitpid, 42]])
      end

      it 'returns 0 when the daemon never reports its pid' do
        allow(rd).to receive(:read).and_return('')
        expect(described_class.call_as_daemon(block)).to eq(0)
      end
    end

    context 'when in a forked copy of the bluepill daemon' do
      before do
        # https://github.com/bluepill-rb/bluepill/issues/1: exit would run
        # the real daemon's ensure blocks in the copy
        allow(described_class).to receive(:exit).and_raise('a forked copy must exit with Process.exit!, not exit')
        allow(described_class).to(receive(:become_daemon)) { |*args| events << [:become_daemon, *args] }
      end

      # Call it until the copy exits with Process.exit!, as it always must
      def call_as_daemon(*args)
        described_class.call_as_daemon(block, *args)
      rescue exited
        nil
      end

      it 'exits the process between with exit!, after starting a session' do
        allow(described_class).to receive(:safefork).and_return(nil, 77)
        call_as_daemon('name')
        expect(events).to eq([[:close, :rd], [:setsid], [:trap, 'SIGHUP', 'IGNORE'], [:close, :wr], [:exit!, true]])
      end

      it 'reports its pid, runs the block as a daemon, and exits with exit!' do
        allow(described_class).to receive(:safefork).and_return(nil, nil)
        call_as_daemon('name')
        expect(events).to eq([[:close, :rd], [:setsid], [:trap, 'SIGHUP', 'IGNORE'], [:write, Process.pid], [:close, :wr],
                              [:become_daemon, 'name'], [:call], [:exit!, true]])
      end

      it 'keeps its process title without a name' do
        allow(described_class).to receive(:safefork).and_return(nil, nil)
        call_as_daemon
        expect(events).to include([:become_daemon, nil])
      end
    end
  end

  describe '.daemonize' do
    before do
      allow(described_class).to(receive(:become_daemon)) { |*args| events << [:become_daemon, *args] }
      allow(described_class).to(receive(:exit)) do |*args|
        events << [:exit, *args]
        raise SystemExit
      end
    end

    # Daemonize until the process exits, as all but the daemon do
    def daemonize
      described_class.daemonize
    rescue SystemExit, exited
      nil
    end

    it 'exits the process that called it, so the command returns' do
      allow(described_class).to receive(:safefork).and_return(1)
      daemonize
      expect(events).to eq([[:exit]])
    end

    it 'exits the session leader with exit!' do
      allow(described_class).to receive(:safefork).and_return(nil, 2)
      daemonize
      expect(events).to eq([[:setsid], [:trap, 'SIGHUP', 'IGNORE'], [:exit!, true]])
    end

    it 'becomes the daemon' do
      allow(described_class).to receive(:safefork).and_return(nil, nil)
      daemonize
      expect(events).to eq([[:setsid], [:trap, 'SIGHUP', 'IGNORE'], [:become_daemon]])
    end

    it "returns the daemon's session id" do
      allow(described_class).to receive(:safefork).and_return(nil, nil)
      expect(described_class.daemonize).to eq(5)
    end
  end

  describe '.detach' do
    it 'returns the session id' do
      expect(described_class.detach).to eq(5)
    end

    it 'starts a session, and then ignores hangups' do
      described_class.detach
      expect(events).to eq([[:setsid], [:trap, 'SIGHUP', 'IGNORE']])
    end

    context 'when there is no session to start' do
      before do
        allow(Process).to(receive(:setsid)) do
          events << [:setsid]
          nil
        end
      end

      # Detach, and carry on past the error
      def detach
        described_class.detach
      rescue Bluepill::Daemonize::Error
        nil
      end

      it 'raises' do
        expect { described_class.detach }.to raise_error(Bluepill::Daemonize::Error, 'cannot detach from controlling terminal')
      end

      it "doesn't ignore hangups" do
        detach
        expect(events).to eq([[:setsid]])
      end
    end
  end

  describe '.become_daemon' do
    around do |example|
      title = $0
      example.run
      $0 = title
    end

    before do
      allow(Dir).to(receive(:chdir)) { |dir| events << [:chdir, dir] }
      [:close_io, :redirect_io, :srand].each do |method|
        allow(described_class).to(receive(method)) { |*args| events << [method, *args] }
      end
    end

    it 'sets the title' do
      described_class.become_daemon('my daemon')
      expect($0).to eq('my daemon')
    end

    it 'leaves its directory, closes and redirects io, and reseeds' do
      described_class.become_daemon('my daemon')
      expect(events).to eq([[:chdir, '/'], [:close_io], [:redirect_io], [:srand]])
    end

    it 'keeps the title without a name' do
      title = $0
      described_class.become_daemon
      expect($0).to eq(title)
    end
  end

  describe '.close_io' do
    # The file descriptors close_io tried to open
    let(:fds) { [] }

    # An open IO, which says in events when it's closed
    def io(name, error = nil)
      instance_double(IO, closed?: false).tap do |io|
        allow(io).to(receive(:close)) do
          events << [:close, name]
          raise error if error
        end
      end
    end

    before do
      ios = [STDIN, io(:open), STDOUT, instance_double(IO, closed?: true), STDERR, io(:failing, IOError)]
      allow(ObjectSpace).to receive(:each_object).with(IO) { |&block| ios.each(&block) }
      allow(IO).to(receive(:for_fd)) do |fd|
        fds << fd
        raise Errno::EBADF unless [3, Bluepill::Daemonize::MAX_FD].include?(fd)

        io(fd)
      end
      [STDIN, STDOUT, STDERR].each { |std| allow(std).to(receive(:close)) { events << [:close, std] } }
    end

    it 'closes every open IO but the standard streams, and then each file descriptor' do
      described_class.close_io
      expect(events).to eq([[:close, :open], [:close, :failing], [:close, 3], [:close, Bluepill::Daemonize::MAX_FD]])
    end

    it 'tries every file descriptor from 3 up' do
      described_class.close_io
      expect(fds).to eq((3..Bluepill::Daemonize::MAX_FD).to_a)
    end

    it 'goes on past a file descriptor that will not close' do
      allow(IO).to receive(:for_fd).with(3).and_return(io(3, IOError))
      described_class.close_io
      expect(events.last).to eq([:close, Bluepill::Daemonize::MAX_FD])
    end
  end

  describe '.redirect_io' do
    # The streams that won't reopen, and what they raise
    let(:failures) { {} }

    before do
      {STDIN => :stdin, STDOUT => :stdout, STDERR => :stderr}.each do |io, name|
        allow(io).to(receive(:reopen)) do |*args|
          events << [name, *args]
          raise failures[name] if failures.key?(name)
        end
      end
      allow(STDERR).to(receive(:sync=)) { |sync| events << [:sync=, sync] }
    end

    it 'points the standard streams at /dev/null' do
      described_class.redirect_io
      expect(events).to eq([[:stdin, File::NULL], [:stdout, File::NULL], [:stderr, STDOUT], [:sync=, true]])
    end

    it 'goes on past a stream that will not reopen' do
      failures.update(stdin: Errno::ENOENT, stderr: IOError)
      described_class.redirect_io
      expect(events).to eq([[:stdin, File::NULL], [:stdout, File::NULL], [:stderr, STDOUT], [:sync=, true]])
    end
  end
end
