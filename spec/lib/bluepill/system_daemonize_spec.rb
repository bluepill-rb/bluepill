# frozen_string_literal: true

require "pathname"

describe Bluepill::System, ".daemonize" do
  let(:rd) { instance_double(IO, close: nil) }
  let(:wr) { instance_double(IO, close: nil, write: nil) }
  let(:logger) { instance_double(Bluepill::Logger) }
  let(:pid_file) { "/var/run/test.pid" }
  let(:options) do
    {
      uid: "user",
      gid: "group",
      supplementary_groups: ["extra"],
      pid_file: pid_file,
      logger: logger,
      stdin: "/dev/null",
      stdout: "out.log",
      stderr: "err.log"
    }
  end

  before do
    allow(IO).to receive(:pipe).and_return([rd, wr])
  end

  # Daemonize, and carry on past the child's exit
  def daemonize(*args)
    described_class.daemonize(*args)
  rescue SystemExit
    nil
  end

  context "when in the parent" do
    before do
      allow(Bluepill::Daemonize).to receive(:safefork).and_return(123)
      allow(Process).to receive(:detach)
      allow(rd).to receive(:read).and_return("456")
    end

    it "detaches the daemon, so it never becomes a zombie" do
      described_class.daemonize("cmd")
      expect(Process).to have_received(:detach).with(123)
    end

    it "returns the pid of the daemon" do
      expect(described_class.daemonize("cmd")).to eq(456)
    end

    it "closes both ends of the pipe" do
      described_class.daemonize("cmd")
      expect([wr, rd]).to all(have_received(:close))
    end

    it "returns any positive pid" do
      allow(rd).to receive(:read).and_return("1")
      expect(described_class.daemonize("cmd")).to eq(1)
    end

    it "returns nil if the child did not report a pid" do
      allow(rd).to receive(:read).and_return("")
      expect(described_class.daemonize("cmd")).to be_nil
    end
  end

  context "when in the child" do
    before do
      allow(Bluepill::Daemonize).to receive(:safefork).and_return(nil)
      allow(described_class).to receive(:drop_privileges)
      allow(described_class).to receive(:redirect_io)
      allow(described_class).to receive(:exit)
      allow(Kernel).to receive(:exec)
      allow(described_class).to receive(:exec).and_raise("exec must be called on Kernel")
      allow(Dir).to receive(:chdir)
      allow(ENV).to receive(:[]=)
      allow(Process).to receive(:exit!)
      allow(described_class).to receive(:exit!).and_raise("exit! must be called on Process")
      allow(File).to receive(:write).with(pid_file, anything)
      allow(Bluepill::Daemonize).to receive(:call_as_daemon) do |block, _|
        block.call
        789
      end
      allow(described_class).to receive(:can_write_pid_file).and_return(true)
    end

    it "does not redirect io that is not configured" do
      described_class.daemonize("cmd", pid_file: pid_file, logger: logger)
      expect(described_class).to have_received(:redirect_io).with(nil, nil, nil)
    end

    it "writes any positive pid to the pid file" do
      allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(1)
      described_class.daemonize("cmd", options)
      expect(File).to have_received(:write).with(pid_file, "1")
    end

    it "reports any positive pid" do
      allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(1)
      described_class.daemonize("cmd", options)
      expect(wr).to have_received(:write).with(1)
    end

    it "does not write a pid of 0 to the pid file" do
      allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(0)
      described_class.daemonize("cmd", options)
      expect(File).not_to have_received(:write)
    end

    it "reports a pid of 0" do
      allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(0)
      described_class.daemonize("cmd", options)
      expect(wr).to have_received(:write).with(0)
    end

    context "when the pid file cannot be written" do
      before do
        allow(described_class).to receive(:can_write_pid_file).with(pid_file, logger).and_return(false)
        allow(described_class).to receive(:exit).with(no_args).and_raise(SystemExit)
      end

      it "exits" do
        expect { described_class.daemonize("cmd", options) }.to raise_error(SystemExit)
      end

      it "checks the pid file once" do
        daemonize("cmd", options)
        expect(described_class).to have_received(:can_write_pid_file).with(pid_file, logger).once
      end

      it "closes the read end of the pipe" do
        daemonize("cmd", options)
        expect(rd).to have_received(:close)
      end

      it "drops privileges first" do
        daemonize("cmd", options)
        expect(described_class).to have_received(:drop_privileges).with("user", "group", ["extra"])
      end

      it "doesn't start the daemon" do
        daemonize("cmd", options)
        expect(Bluepill::Daemonize).not_to have_received(:call_as_daemon)
      end
    end

    context "without options" do
      before do
        allow(described_class).to receive(:can_write_pid_file).with(nil, nil).and_return(false)
        allow(described_class).to receive(:exit).with(no_args).and_raise(SystemExit)
      end

      it "exits" do
        expect { described_class.daemonize("cmd") }.to raise_error(SystemExit)
      end

      it "checks that there is no pid file to write" do
        daemonize("cmd")
        expect(described_class).to have_received(:can_write_pid_file).with(nil, nil)
      end

      it "drops no privileges" do
        daemonize("cmd")
        expect(described_class).to have_received(:drop_privileges).with(nil, nil, nil)
      end
    end

    context "when it daemonizes a command" do
      before do
        described_class.daemonize('echo "hello world"', options)
      end

      it "stays in its directory" do
        expect(Dir).not_to have_received(:chdir)
      end

      it "keeps its environment" do
        expect(ENV).not_to have_received(:[]=)
      end

      it "redirects io" do
        expect(described_class).to have_received(:redirect_io).with(File::NULL, "out.log", "err.log")
      end

      it "execs the command" do
        expect(Kernel).to have_received(:exec).with("echo", "hello world")
      end

      it "exits if the exec returns" do
        expect(described_class).to have_received(:exit).with(no_args)
      end

      it "runs the command as a daemon, titled with the command" do
        expect(Bluepill::Daemonize).to have_received(:call_as_daemon).with(kind_of(Proc), 'echo "hello world"')
      end

      it "writes the daemon's pid to the pid file" do
        expect(File).to have_received(:write).with(pid_file, "789")
      end

      it "reports the daemon's pid" do
        expect(wr).to have_received(:write).with(789)
      end

      it "closes the write end of the pipe" do
        expect(wr).to have_received(:close)
      end

      it "exits with exit!" do
        expect(Process).to have_received(:exit!).with(true)
      end
    end

    context "with a working directory and an environment" do
      before do
        described_class.daemonize("cmd", options.merge(working_dir: Pathname.new("/tmp/work"), environment: {FOO: 1}))
      end

      it "sets PWD to the working directory" do
        expect(ENV).to have_received(:[]=).with("PWD", "/tmp/work")
      end

      it "changes to the working directory" do
        expect(Dir).to have_received(:chdir).with("/tmp/work")
      end

      it "sets the environment" do
        expect(ENV).to have_received(:[]=).with("FOO", "1")
      end
    end
  end
end
