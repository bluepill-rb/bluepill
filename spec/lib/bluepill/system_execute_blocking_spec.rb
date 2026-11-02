# frozen_string_literal: true

require "pathname"
require "tmpdir"

describe Bluepill::System, ".execute_blocking" do
  let(:rd) { instance_double(IO, close: nil) }
  let(:wr) { instance_double(IO, close: nil, write: nil) }

  context "when in the parent" do
    let(:waiter) { instance_double(Thread, join: nil) }

    before do
      allow(IO).to receive(:pipe).and_return([rd, wr])
      allow(Bluepill::Daemonize).to receive(:safefork).and_return(123)
      allow(Process).to receive(:detach).with(123).and_return(waiter)
      allow(rd).to receive(:read).and_return("")
    end

    it "returns the result reported by the child" do
      result = {exit_code: 1, stdout: "out", stderr: "err"}
      allow(rd).to receive(:read).and_return(Marshal.dump(result))
      expect(described_class.execute_blocking("cmd")).to eq(result)
    end

    it "closes both ends of the pipe" do
      described_class.execute_blocking("cmd")
      expect([wr, rd]).to all(have_received(:close))
    end

    it "returns an empty successful result if the child reported nothing" do
      expect(described_class.execute_blocking("cmd")).to eq(exit_code: 0, stdout: "", stderr: "")
    end

    it "detaches the child" do
      described_class.execute_blocking("cmd")
      expect(Process).to have_received(:detach).with(123)
    end

    it "waits for the child to be reaped" do
      described_class.execute_blocking("cmd")
      expect(waiter).to have_received(:join)
    end

    it "gives IO.select a timeout it can read, from a duration too" do
      allow(IO).to receive(:select).and_return([[rd], [], []])
      described_class.execute_blocking("cmd", timeout: 2.seconds)
      expect(IO).to have_received(:select).with([rd], nil, nil, an_instance_of(Float)).once
    end

    it "times out even if the command has just finished" do
      allow(IO).to receive(:select).and_return(nil)
      allow(Process).to receive(:kill).with("KILL", -123).and_raise(Errno::ESRCH)
      expect { described_class.execute_blocking("cmd", timeout: 2) }.to raise_error(Timeout::Error)
    end

    context "with a timeout the command finishes within" do
      before do
        allow(IO).to receive(:select).with([rd], nil, nil, 2.5).and_return([[rd], [], []])
        allow(Process).to receive(:kill)
      end

      it "returns its result" do
        expect(described_class.execute_blocking("cmd", timeout: 2.5)).to eq(exit_code: 0, stdout: "", stderr: "")
      end

      it "waits for its result for that long, once" do
        described_class.execute_blocking("cmd", timeout: 2.5)
        expect(IO).to have_received(:select).once
      end

      it "doesn't kill it" do
        described_class.execute_blocking("cmd", timeout: 2.5)
        expect(Process).not_to have_received(:kill)
      end
    end

    context "with a timeout the command runs past" do
      before do
        allow(IO).to receive(:select).with([rd], nil, nil, 2.0).and_return(nil)
        allow(Process).to receive(:kill)
      end

      # Run the command, and carry on past the timeout
      def execute_blocking
        described_class.execute_blocking("cmd", timeout: 2)
      rescue Timeout::Error
        nil
      end

      it "raises" do
        expect { described_class.execute_blocking("cmd", timeout: 2) }
          .to raise_error(Timeout::Error, "cmd took longer than 2 seconds")
      end

      it "waits for its result for that long, once" do
        execute_blocking
        expect(IO).to have_received(:select).once
      end

      it "kills the command's process group" do
        execute_blocking
        expect(Process).to have_received(:kill).with("KILL", -123).once
      end

      it "reads no result" do
        execute_blocking
        expect(rd).not_to have_received(:read)
      end

      it "closes the pipe" do
        execute_blocking
        expect(rd).to have_received(:close)
      end
    end

    context "when interrupted by a timeout" do
      before do
        allow(rd).to receive(:read).and_raise(Timeout::Error)
      end

      # Run the command, and carry on past the timeout
      def execute_blocking
        described_class.execute_blocking("cmd")
      rescue Timeout::Error
        nil
      end

      it "raises" do
        expect { described_class.execute_blocking("cmd") }.to raise_error(Timeout::Error)
      end

      it "reaps the child" do
        execute_blocking
        expect(Process).to have_received(:detach).with(123)
      end

      it "closes the pipe" do
        execute_blocking
        expect(rd).to have_received(:close)
      end

      it "doesn't wait for the child" do
        execute_blocking
        expect(waiter).not_to have_received(:join)
      end
    end
  end

  context "with a command that hangs, and starts a process of its own", if: RUBY_ENGINE == "ruby" do
    let(:dir) { Dir.mktmpdir }

    after do
      FileUtils.remove_entry(dir)
    end

    # Run a command that starts a sleep of its own, and hangs, until it
    # times out. Return whether the sleep is still alive after that.
    def sleep_alive_after_timeout
      pid_file = File.join(dir, "pid")
      cmd = %(#{RbConfig.ruby} -e "File.write('#{pid_file}', Process.spawn('sleep', '30').to_s)\nsleep 30")
      described_class.execute_blocking(cmd, timeout: 2)
    rescue Timeout::Error
      sleep_pid = Integer(File.read(pid_file))
      # Killed, and reaped by init, since the command that started it is gone
      Timeout.timeout(5) { sleep 0.1 while described_class.pid_alive?(sleep_pid) }
      described_class.pid_alive?(sleep_pid)
    end

    it "times out, and kills it and what it started" do
      expect(sleep_alive_after_timeout).to be false
    end
  end

  context "when in the child" do
    # The read and write ends of the command's stdout and stderr pipes
    let(:out) { [instance_double(IO, close: nil, read: "out"), instance_double(IO, close: nil)] }
    let(:err) { [instance_double(IO, close: nil, read: "err"), instance_double(IO, close: nil, puts: nil, closed?: false)] }
    let(:options) { {uid: "user", gid: "group", supplementary_groups: ["extra"]} }

    before do
      allow(IO).to receive(:pipe).and_return([rd, wr], out, err)
      allow(Bluepill::Daemonize).to receive(:safefork).and_return(nil)
      allow(described_class).to receive(:fork) do |&block|
        block.call
        456
      end
      allow(described_class).to receive(:drop_privileges)
      allow(described_class).to receive(:exit)
      allow(Dir).to receive(:chdir)
      allow(ENV).to receive(:[]=)
      allow(STDIN).to receive(:reopen)
      allow(STDOUT).to receive(:reopen)
      allow(STDERR).to receive(:reopen)
      allow(STDERR).to receive(:puts)
      allow(Kernel).to receive(:exec)
      allow(described_class).to receive(:exec).and_raise("exec must be called on Kernel")
      allow(Process).to receive(:waitpid2).with(456).and_return([456, instance_double(Process::Status, exitstatus: 2)])
      allow(Process).to receive(:exit!)
      allow(Process).to receive(:setpgid)
    end

    it "leads a process group of its own with a timeout" do
      described_class.execute_blocking("echo", timeout: 5)
      expect(Process).to have_received(:setpgid).with(0, 0).once
    end

    it "stays in bluepill's process group without a timeout" do
      described_class.execute_blocking("echo")
      expect(Process).not_to have_received(:setpgid)
    end

    it "stays in bluepill's process group with a nil timeout" do
      described_class.execute_blocking("echo", timeout: nil)
      expect(Process).not_to have_received(:setpgid)
    end

    it "drops no privileges without options" do
      described_class.execute_blocking("cmd")
      expect(described_class).to have_received(:drop_privileges).with(nil, nil, nil)
    end

    it "execs the command without options" do
      described_class.execute_blocking("cmd")
      expect(Kernel).to have_received(:exec).with("cmd")
    end

    context "when it execs a command" do
      before do
        described_class.execute_blocking('echo "hello world"', options)
      end

      it "closes the read end of the result pipe" do
        expect(rd).to have_received(:close)
      end

      it "drops privileges" do
        expect(described_class).to have_received(:drop_privileges).with("user", "group", ["extra"])
      end

      it "stays in its directory" do
        expect(Dir).not_to have_received(:chdir)
      end

      it "keeps its environment" do
        expect(ENV).not_to have_received(:[]=)
      end

      it "closes the write end of the result pipe in the grandchild, and then in the child" do
        expect(wr).to have_received(:close).twice
      end

      it "reads nothing on stdin" do
        expect(STDIN).to have_received(:reopen).with(File::NULL)
      end

      it "sends stdout to its pipe" do
        expect(STDOUT).to have_received(:reopen).with(out.last)
      end

      it "sends stderr to its pipe" do
        expect(STDERR).to have_received(:reopen).with(err.last)
      end

      it "execs the command" do
        expect(Kernel).to have_received(:exec).with("echo", "hello world")
      end

      it "closes both ends of the output pipes in the grandchild and the child" do
        expect(out + err).to all(have_received(:close).twice)
      end

      it "reports its output and exit code" do
        expect(wr).to have_received(:write).with(Marshal.dump(stdout: "out", stderr: "err", exit_code: 2))
      end

      it "exits with exit!" do
        expect(Process).to have_received(:exit!).with(no_args)
      end
    end

    context "when the parent stopped waiting for the result" do
      before do
        allow(wr).to receive(:write).and_raise(Errno::EPIPE)
        described_class.execute_blocking("cmd", options)
      end

      it "still closes the result pipe" do
        expect(wr).to have_received(:close).twice
      end

      it "still exits" do
        expect(Process).to have_received(:exit!).with(no_args)
      end
    end

    context "with a working directory and an environment" do
      before do
        described_class.execute_blocking("cmd", options.merge(working_dir: Pathname.new("/tmp/work"), environment: {FOO: 1}))
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

    context "when it fails before the exec, with the stderr pipe open" do
      before do
        allow(described_class).to receive(:drop_privileges).and_raise(ArgumentError, "no such user")
        described_class.execute_blocking("cmd", options)
      end

      it "reports the exception on the stderr pipe" do
        expect(err.last).to have_received(:puts).with("Exception in grandchild: no such user.")
      end

      it "reports its backtrace on the stderr pipe" do
        expect(err.last).to have_received(:puts).with(kind_of(Array))
      end

      it "doesn't exec the command" do
        expect(Kernel).not_to have_received(:exec)
      end

      it "exits with 1" do
        expect(described_class).to have_received(:exit).with(1)
      end
    end

    context "when the exec fails, with the stderr pipe closed" do
      before do
        allow(err.last).to receive(:closed?).and_return(true)
        allow(Kernel).to receive(:exec).and_raise(Errno::ENOENT, "cmd")
        described_class.execute_blocking("cmd", options)
      end

      it "reports the exception on STDERR" do
        expect(STDERR).to have_received(:puts).with("Exception in grandchild: No such file or directory - cmd.")
      end

      it "reports its backtrace on STDERR" do
        expect(STDERR).to have_received(:puts).with(kind_of(Array))
      end

      it "doesn't report on the stderr pipe" do
        expect(err.last).not_to have_received(:puts)
      end

      it "exits with 1" do
        expect(described_class).to have_received(:exit).with(1)
      end
    end
  end
end
