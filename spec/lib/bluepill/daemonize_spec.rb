# frozen_string_literal: true

describe Bluepill::Daemonize do
  # Stands in for Kernel.exit!, which would end the spec run
  let(:exited) { Class.new(StandardError) }
  # What the daemon does to the system, in order
  let(:events) { [] }

  before do
    allow(Kernel).to(receive(:exit!)) do |*args|
      events << [:exit!, *args]
      raise exited
    end
    allow(described_class).to receive(:exit!).and_raise("exit! must be called on Kernel")
    allow(Process).to(receive(:waitpid)) { |pid| events << [:waitpid, pid] }
    allow(Process).to(receive(:setsid)) do
      events << [:setsid]
      5
    end
    allow(Signal).to(receive(:trap)) { |*args| events << [:trap, *args] }
  end

  describe "CAN_FORK" do
    it "is whether Process can fork, which JRuby's can't" do
      expect(described_class::CAN_FORK).to be(Process.respond_to?(:fork))
    end
  end

  describe ".can_fork?" do
    it "is true when Ruby can fork" do
      stub_const("Bluepill::Daemonize::CAN_FORK", true)
      expect(described_class.can_fork?).to be(true)
    end

    it "is false when it can't, as on JRuby" do
      stub_const("Bluepill::Daemonize::CAN_FORK", false)
      expect(described_class.can_fork?).to be(false)
    end
  end

  describe ".safefork" do
    it "returns the child pid in the parent" do
      allow(described_class).to receive(:fork).and_return(123)
      expect(described_class.safefork).to eq(123)
    end

    it "returns nil in the child" do
      allow(described_class).to receive(:fork).and_return(nil)
      expect(described_class.safefork).to be_nil
    end

    context "when the system is out of processes at first" do
      before do
        calls = 0
        allow(described_class).to receive(:fork) do
          calls += 1
          raise Errno::EWOULDBLOCK if calls < 3

          7
        end
        allow(described_class).to receive(:sleep)
      end

      it "returns the child pid once a fork works" do
        expect(described_class.safefork).to eq(7)
      end

      it "waits 5 seconds before each retry" do
        described_class.safefork
        expect(described_class).to have_received(:sleep).with(5).twice
      end
    end
  end

  describe ".call_as_daemon" do
    let(:rd) { instance_double(IO, read: "") }
    let(:wr) { instance_double(IO) }
    let(:block) { instance_double(Proc) }

    before do
      allow(IO).to receive(:pipe).and_return([rd, wr])
      allow(rd).to(receive(:close)) { events << %i[close rd] }
      allow(wr).to(receive(:close)) { events << %i[close wr] }
      allow(wr).to(receive(:write)) { |data| events << [:write, data] }
      allow(block).to(receive(:call)) { events << [:call] }
    end

    context "when in the process that called it" do
      before do
        allow(described_class).to receive(:safefork).and_return(42)
        allow(rd).to receive(:read).and_return("99")
      end

      it "returns the pid the daemon reports, once the process between exits" do
        expect(described_class.call_as_daemon(block, "name")).to eq(99)
      end

      it "closes the pipe and waits for the process between, without running the block" do
        described_class.call_as_daemon(block, "name")
        expect(events).to eq([%i[close wr], %i[close rd], [:waitpid, 42]])
      end

      it "returns 0 when the daemon never reports its pid" do
        allow(rd).to receive(:read).and_return("")
        expect(described_class.call_as_daemon(block)).to eq(0)
      end
    end

    context "when in a forked copy of the bluepill daemon" do
      before do
        # https://github.com/bluepill-rb/bluepill/issues/1: exit would run
        # the real daemon's ensure blocks in the copy
        allow(described_class).to receive(:exit).and_raise("a forked copy must exit with Kernel.exit!, not exit")
        allow(described_class).to(receive(:become_daemon)) { |*args| events << [:become_daemon, *args] }
      end

      # Call it until the copy exits with Kernel.exit!, as it always must
      def call_as_daemon(*args)
        described_class.call_as_daemon(block, *args)
      rescue exited
        nil
      end

      it "exits the process between with exit!, after starting a session" do
        allow(described_class).to receive(:safefork).and_return(nil, 77)
        call_as_daemon("name")
        expect(events).to eq([%i[close rd], [:setsid], [:trap, "SIGHUP", "IGNORE"], %i[close wr], [:exit!, true]])
      end

      it "reports its pid, runs the block as a daemon, and exits with exit!" do
        allow(described_class).to receive(:safefork).and_return(nil, nil)
        call_as_daemon("name")
        expect(events).to eq([%i[close rd], [:setsid], [:trap, "SIGHUP", "IGNORE"], [:write, Process.pid], %i[close wr],
          [:become_daemon, "name"], [:call], [:exit!, true]])
      end

      it "keeps its process title without a name" do
        allow(described_class).to receive(:safefork).and_return(nil, nil)
        call_as_daemon
        expect(events).to include([:become_daemon, nil])
      end
    end
  end

  describe ".daemonize" do
    before do
      allow(described_class).to receive(:can_fork?).and_return(true)
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

    it "exits the process that called it, so the command returns" do
      allow(described_class).to receive(:safefork).and_return(1)
      daemonize
      expect(events).to eq([[:exit]])
    end

    it "exits the session leader with exit!" do
      allow(described_class).to receive(:safefork).and_return(nil, 2)
      daemonize
      expect(events).to eq([[:setsid], [:trap, "SIGHUP", "IGNORE"], [:exit!, true]])
    end

    it "becomes the daemon" do
      allow(described_class).to receive(:safefork).and_return(nil, nil)
      daemonize
      expect(events).to eq([[:setsid], [:trap, "SIGHUP", "IGNORE"], [:become_daemon]])
    end

    it "returns the daemon's session id" do
      allow(described_class).to receive(:safefork).and_return(nil, nil)
      expect(described_class.daemonize).to eq(5)
    end

    context "when it can't fork" do
      before do
        allow(described_class).to receive_messages(can_fork?: false, daemonize_without_fork: 9)
        allow(described_class).to receive(:safefork)
      end

      it "daemonizes without forking" do
        expect(described_class.daemonize).to eq(9)
      end

      it "doesn't fork" do
        described_class.daemonize
        expect(described_class).not_to have_received(:safefork)
      end
    end
  end

  describe ".daemonize_without_fork" do
    around do |example|
      daemon = ENV.delete("BLUEPILL_DAEMON")
      example.run
    ensure
      daemon ? ENV["BLUEPILL_DAEMON"] = daemon : ENV.delete("BLUEPILL_DAEMON")
    end

    before do
      allow(described_class).to(receive(:start_daemon_bluepill)) { events << [:start_daemon_bluepill] }
      allow(Dir).to(receive(:chdir)) { |dir| events << [:chdir, dir] }
    end

    it "starts a bluepill to be the daemon" do
      described_class.daemonize_without_fork
      expect(events.first).to eq([:start_daemon_bluepill])
    end

    context "when in the bluepill it started" do
      before { ENV["BLUEPILL_DAEMON"] = "1" }

      it "starts a session, ignores hangups, and leaves its directory" do
        described_class.daemonize_without_fork
        expect(events).to eq([[:setsid], [:trap, "SIGHUP", "IGNORE"], [:chdir, "/"]])
      end

      it "takes the variable out of its environment, so its commands don't get it" do
        described_class.daemonize_without_fork
        expect(ENV).not_to have_key("BLUEPILL_DAEMON")
      end

      it "returns the daemon's session id" do
        expect(described_class.daemonize_without_fork).to eq(5)
      end
    end
  end

  describe ".start_daemon_bluepill" do
    around do |example|
      title = $0
      $0 = "app.pill"
      example.run
    ensure
      $0 = title
    end

    before do
      stub_const("ARGV", ["--flag"])
      allow(Kernel).to(receive(:spawn)) { |*args, **options| events << [:spawn, *args, options] }
      allow(described_class).to(receive(:exit)) do
        events << [:exit]
        raise SystemExit
      end
    end

    # Start the daemon's bluepill, and carry on past the exit
    def start_daemon_bluepill
      described_class.start_daemon_bluepill
    rescue SystemExit
      nil
    end

    it "spawns a bluepill that runs the pill file, marked as the daemon, and then exits" do
      lib = File.expand_path("../../../lib", __dir__)
      start_daemon_bluepill
      expect(events).to eq([[:spawn, {"BLUEPILL_DAEMON" => "1"}, RbConfig.ruby, "-I#{lib}", "-rbluepill",
        File.expand_path("app.pill"), "--flag", {in: File::NULL, out: File::NULL, err: File::NULL}], [:exit]])
    end
  end

  describe ".detach" do
    it "returns the session id" do
      expect(described_class.detach).to eq(5)
    end

    it "starts a session, and then ignores hangups" do
      described_class.detach
      expect(events).to eq([[:setsid], [:trap, "SIGHUP", "IGNORE"]])
    end

    context "when there is no session to start" do
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

      it "raises" do
        message = "cannot detach from controlling terminal"
        expect { described_class.detach }.to raise_error(Bluepill::Daemonize::Error, message)
      end

      it "doesn't ignore hangups" do
        detach
        expect(events).to eq([[:setsid]])
      end
    end
  end

  describe ".become_daemon" do
    around do |example|
      title = $0
      example.run
      $0 = title
    end

    before do
      allow(Dir).to(receive(:chdir)) { |dir| events << [:chdir, dir] }
      %i[close_io redirect_io srand].each do |method|
        allow(described_class).to(receive(method)) { |*args| events << [method, *args] }
      end
    end

    it "sets the title" do
      described_class.become_daemon("my daemon")
      expect($0).to eq("my daemon")
    end

    it "leaves its directory, closes and redirects io, and reseeds" do
      described_class.become_daemon("my daemon")
      expect(events).to eq([[:chdir, "/"], [:close_io], [:redirect_io], [:srand]])
    end

    it "keeps the title without a name" do
      title = $0
      described_class.become_daemon
      expect($0).to eq(title)
    end
  end

  describe ".close_io" do
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

    it "closes every open IO but the standard streams, and then each file descriptor" do
      described_class.close_io
      expect(events).to eq([%i[close open], %i[close failing], [:close, 3], [:close, Bluepill::Daemonize::MAX_FD]])
    end

    it "tries every file descriptor from 3 up" do
      described_class.close_io
      expect(fds).to eq((3..Bluepill::Daemonize::MAX_FD).to_a)
    end

    it "goes on past a file descriptor that will not close" do
      allow(IO).to receive(:for_fd).with(3).and_return(io(3, IOError))
      described_class.close_io
      expect(events.last).to eq([:close, Bluepill::Daemonize::MAX_FD])
    end
  end

  describe ".redirect_io" do
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

    it "points the standard streams at /dev/null" do
      described_class.redirect_io
      expect(events).to eq([[:stdin, File::NULL], [:stdout, File::NULL], [:stderr, STDOUT], [:sync=, true]])
    end

    it "goes on past a stream that will not reopen" do
      failures.update(stdin: Errno::ENOENT, stderr: IOError)
      described_class.redirect_io
      expect(events).to eq([[:stdin, File::NULL], [:stdout, File::NULL], [:stderr, STDOUT], [:sync=, true]])
    end

    it "goes on past standard output if it will not reopen" do
      failures.update(stdout: Errno::ENOENT)
      described_class.redirect_io
      expect(events).to eq([[:stdin, File::NULL], [:stdout, File::NULL], [:stderr, STDOUT], [:sync=, true]])
    end
  end
end
