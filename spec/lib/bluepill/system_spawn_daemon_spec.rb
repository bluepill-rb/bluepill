# frozen_string_literal: true

describe Bluepill::System, ".spawn_daemon" do
  context "when daemonize can't fork" do
    let(:logger) { instance_double(Bluepill::Logger) }
    let(:dir) { Dir.mktmpdir }
    let(:pid_file) { File.join(dir, "daemon.pid") }
    let(:spawned) { [] }

    before do
      allow(Bluepill::Daemonize).to receive(:can_fork?).and_return(false)
      allow(Bluepill::Daemonize).to receive(:safefork)
      allow(IO).to receive(:pipe).and_call_original
    end

    after do
      spawned.each { |pid| stop(pid) }
      FileUtils.remove_entry(dir)
    end

    # Kill a spawned daemon if it's still running, and reap it
    def stop(pid)
      Process.kill("KILL", pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end

    # Start a daemon of the command, and keep its pid to stop it after
    def start(cmd, **options)
      pid = described_class.daemonize(cmd, Bluepill::System::CommandOptions.new(**options), pid_file:, logger:)
      spawned << pid if pid
      pid
    end

    # Start a daemon of the command, and wait for it to finish
    def run_to_end(cmd, **options) = Process.wait(start(cmd, **options))

    # The contents of a file in the directory
    def read(name) = File.read(File.join(dir, name))

    it "returns the pid of the daemon, which runs the command" do
      expect(Process.kill(0, start("sleep 5"))).to eq(1)
    end

    it "doesn't fork" do
      start("sleep 5")
      expect(Bluepill::Daemonize).not_to have_received(:safefork)
    end

    it "writes the daemon's pid to the pid file" do
      pid = start("sleep 5")
      expect(File.read(pid_file)).to eq(pid.to_s)
    end

    it "writes the pid as a string with File.write" do
      allow(File).to receive(:write).and_call_original
      pid = start("sleep 5")
      expect(File).to have_received(:write).with(pid_file, pid.to_s)
    end

    it "runs the daemon in a process group of its own" do
      pid = start("sleep 5")
      expect(Process.getpgid(pid)).to eq(pid)
    end

    it "runs the daemon in / without a working_dir" do
      run_to_end("sh -c 'pwd -P > #{dir}/pwd'")
      expect(read("pwd")).to eq("/\n")
    end

    it "runs the daemon in its working_dir" do
      run_to_end("sh -c 'pwd -P > pwd'", working_dir: dir)
      expect(read("pwd")).to eq("#{File.realpath(dir)}\n")
    end

    it "sets PWD to the working_dir, and the environment" do
      run_to_end(%(sh -c 'echo "$PWD $FOO" > env'), working_dir: dir, environment: {FOO: 1})
      expect(read("env")).to eq("#{dir} 1\n")
    end

    it "appends standard output and standard error to their files" do
      File.write(File.join(dir, "out"), "old\n")
      run_to_end("sh -c 'echo out; echo err >&2'", stdout: File.join(dir, "out"), stderr: File.join(dir, "err"))
      expect([read("out"), read("err")]).to eq(["old\nout\n", "err\n"])
    end

    it "puts standard output and standard error in one file when they name the same one" do
      log = File.join(dir, "log")
      run_to_end("sh -c 'echo out; echo err >&2'", stdout: log, stderr: log.dup)
      expect(read("log")).to eq("out\nerr\n")
    end

    it "reads standard input from a file" do
      File.write(File.join(dir, "in"), "hello")
      run_to_end("sh -c 'cat > copy'", working_dir: dir, stdin: File.join(dir, "in"))
      expect(read("copy")).to eq("hello")
    end

    it "doesn't start a daemon whose pid file can't be written" do
      allow(described_class).to receive(:can_write_pid_file).with(pid_file, logger).and_return(false)
      expect(start("sleep 5")).to be_nil
    end

    context "with a program that can't be run" do
      # JRuby spawns a child that exits instead of raising
      before do
        allow(Kernel).to receive(:spawn).and_raise(Errno::ENOENT, "no-such-bluepill-program")
        allow(logger).to receive(:warning).and_return(true)
      end

      it "returns nil" do
        expect(start("no-such-bluepill-program")).to be_nil
      end

      it "logs why it didn't start" do
        start("no-such-bluepill-program")
        expect(logger).to have_received(:warning).with(/\AErrno::ENOENT - .*no-such-bluepill-program/)
      end

      it "doesn't write the pid file" do
        start("no-such-bluepill-program")
        expect(File).not_to exist(pid_file)
      end
    end
  end

  describe ".daemon_streams" do
    # Where a daemon with these options has its standard streams
    def streams(**options) = described_class.daemon_streams(Bluepill::System::CommandOptions.new(**options))

    it "points them at /dev/null without files" do
      expect(streams).to eq(in: File::NULL, out: File::NULL, err: File::NULL)
    end

    it "sends standard error to standard output when they name the same file" do
      expect(streams(stdout: "log", stderr: +"log")).to eq(in: File::NULL, out: ["log", "a"], err: [:child, :out])
    end

    it "reads standard input from its file, and appends to the others" do
      expect(streams(stdin: "in", stdout: "out", stderr: "err")).to eq(in: "in", out: ["out", "a"], err: ["err", "a"])
    end
  end

  describe ".daemon_stderr" do
    it "is /dev/null without a file" do
      expect(described_class.daemon_stderr("out", nil)).to eq(File::NULL)
    end

    it "is standard output when it names the same file" do
      expect(described_class.daemon_stderr("log", +"log")).to eq([:child, :out])
    end

    it "appends to a file of its own" do
      expect(described_class.daemon_stderr("out", "err")).to eq(["err", "a"])
    end

    it "appends to its file without one for standard output" do
      expect(described_class.daemon_stderr(nil, "err")).to eq(["err", "a"])
    end
  end
end
