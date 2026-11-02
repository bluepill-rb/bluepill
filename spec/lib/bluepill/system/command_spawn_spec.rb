# frozen_string_literal: true

require "pathname"
require "tmpdir"

describe Bluepill::System::CommandSpawn do
  let(:spawner) { Bluepill::System }

  let(:dir) { File.realpath(Dir.mktmpdir) }

  after { FileUtils.remove_entry(dir) }

  def opts(**options) = Bluepill::System::CommandOptions.new(**options)

  # Spawn a command with its output in a file, wait for it, and return what
  # it printed
  def output_of(cmd, options = opts, **redirects)
    file = File.join(dir, "out")
    Process.wait(spawner.spawn_command(cmd, options, out: [file, "w"], **redirects))
    File.read(file)
  end

  # Wait up to 5 seconds for a process to be gone
  def gone?(pid)
    Timeout.timeout(5) { sleep 0.05 while spawner.pid_alive?(pid) }
    true
  end

  # Record the pid of each command spawned
  def record_spawns
    pids = []
    record = ->(spawn, *args, **kw) { spawn.call(*args, **kw).tap { |pid| pids << pid } }
    allow(Process).to receive(:spawn).and_wrap_original(&record)
    pids
  end

  # Return whether a pid can no longer be waited for, since it was reaped
  def reaped?(pid)
    Process.wait(pid, Process::WNOHANG)
    false
  rescue Errno::ECHILD
    true
  end

  describe "#spawn_command" do
    it "runs the command, split into words, and returns its pid" do
      Process.wait(spawner.spawn_command("sh -c 'exit 3'", opts))
      expect($?.exitstatus).to eq(3)
    end

    it "gives it the environment, and the working directory as PWD" do
      options = opts(working_dir: dir, environment: {FOO: 1})
      expect(output_of('sh -c "echo $FOO $PWD $(pwd)"', options)).to eq("1 #{dir} #{dir}\n")
    end

    it "runs it in chdir without a working directory" do
      expect(output_of("pwd", opts, chdir: dir)).to eq("#{dir}\n")
    end

    it "runs it in the working directory, not chdir" do
      expect(output_of("pwd", opts(working_dir: dir), chdir: "/")).to eq("#{dir}\n")
    end

    it "runs it in bluepill's directory without either" do
      expect(output_of("pwd")).to eq("#{File.realpath(Dir.pwd)}\n")
    end

    it "passes the working directory to Process.spawn as a String" do
      allow(Process).to receive(:spawn).and_return(7)
      spawner.spawn_command("prog a", opts(working_dir: Pathname(dir)), out: :err)
      expect(Process).to have_received(:spawn).with({"PWD" => dir}, "prog", "a", out: :err, chdir: dir)
    end

    it "raises for an empty command" do
      expect { spawner.spawn_command("", opts) }.to raise_error(SystemCallError)
    end
  end

  describe "#spawn_environment" do
    it "has the environment's keys and values as Strings" do
      expect(spawner.spawn_environment(opts(environment: {FOO: 1}))).to eq("FOO" => "1")
    end

    it "sets PWD to the working directory" do
      expect(spawner.spawn_environment(opts(working_dir: Pathname("/srv")))).to eq("PWD" => "/srv")
    end

    it "lets the environment set PWD" do
      options = opts(working_dir: "/srv", environment: {"PWD" => "/other"})
      expect(spawner.spawn_environment(options)).to eq("PWD" => "/other")
    end
  end

  describe "#spawn_blocking" do
    it "returns what the command printed, and its exit code" do
      result = spawner.spawn_blocking("sh -c 'echo out; echo err >&2; exit 3'", opts)
      expect(result.to_h).to eq(exit_code: 3, stdout: "out\n", stderr: "err\n")
    end

    it "has no exit code when a signal ended it" do
      expect(spawner.spawn_blocking("sh -c 'kill -9 $$'", opts).exit_code).to be_nil
    end

    it "reads both pipes at once, so neither fills up and stops the command" do
      cmd = "sh -c 'head -c 200000 /dev/zero >&2; head -c 200000 /dev/zero'"
      result = Timeout.timeout(10) { spawner.spawn_blocking(cmd, opts) }
      expect([result.stdout.size, result.stderr.size]).to eq([200_000, 200_000])
    end

    it "gives the command /dev/null for standard input" do
      allow(Process).to receive(:spawn).and_call_original
      spawner.spawn_blocking("true", opts)
      expect(Process).to have_received(:spawn).with(anything, "true", hash_including(in: File::NULL))
    end

    it "runs the command in its working directory, with its environment" do
      result = spawner.spawn_blocking('sh -c "echo $FOO; pwd"', opts(working_dir: dir, environment: {FOO: "bar"}))
      expect(result.stdout).to eq("bar\n#{dir}\n")
    end

    it "returns exit code 1 and why for a command that can't be run" do
      result = spawner.spawn_blocking("no-such-program-for-bluepill", opts)
      expect([result.exit_code, result.stdout]).to eq([1, ""])
    end

    it "says why with the error's message" do
      error = Errno::ENOENT.new("prog")
      def error.message = "the message"
      allow(Process).to receive(:spawn).and_raise(error)
      expect(spawner.spawn_blocking("prog", opts).stderr).to eq("Could not run prog: the message\n")
    end

    it "says why a command can't be run on standard error" do
      stderr = spawner.spawn_blocking("no-such-program-for-bluepill", opts).stderr
      expect(stderr).to match(/\ACould not run no-such-program-for-bluepill: \S.*\n\z/)
    end

    it "runs the command in bluepill's process group without a timeout" do
      result = spawner.spawn_blocking("sh -c 'ps -o pgid= -p $$'", opts)
      expect(result.stdout.strip).to eq(Process.getpgrp.to_s)
    end

    it "runs the command in a process group of its own with a timeout" do
      pids = record_spawns
      result = spawner.spawn_blocking("sh -c 'ps -o pgid= -p $$'", opts(timeout: 5))
      expect(result.stdout.strip).to eq(pids.first.to_s)
    end

    it "returns what a command that finished in time printed" do
      result = spawner.spawn_blocking("echo done", opts(timeout: 5))
      expect(result.to_h).to eq(exit_code: 0, stdout: "done\n", stderr: "")
    end

    context "with pipes it can watch" do
      let(:pipes) { [] }

      before do
        allow(IO).to(receive(:pipe).and_wrap_original { |pipe| pipe.call.tap { |ends| pipes.concat(ends) } })
      end

      it "closes the pipes" do
        spawner.spawn_blocking("echo hi", opts)
        expect(pipes.collect(&:closed?)).to eq([true] * 4)
      end

      it "closes the pipes of a command that can't be run" do
        spawner.spawn_blocking("no-such-program-for-bluepill", opts)
        expect(pipes.collect(&:closed?)).to eq([true] * 4)
      end
    end

    # A second, so a loaded machine starts the sleep and writes its pid file in time
    context "with a command that runs past its timeout" do
      let(:pid_file) { File.join(dir, "pid") }
      let(:cmd) { "sh -c 'sleep 30 & echo $! > #{pid_file}; wait'" }

      # Run the command, and carry on past the timeout
      def run_past_timeout
        spawner.spawn_blocking(cmd, opts(timeout: 1))
      rescue Timeout::Error
        nil
      end

      it "raises" do
        expect { spawner.spawn_blocking(cmd, opts(timeout: 1)) }
          .to raise_error(Timeout::Error, "#{cmd} took longer than 1 seconds")
      end

      it "kills what the command started too" do
        run_past_timeout
        expect(gone?(Integer(File.read(pid_file)))).to be true
      end

      it "collects the command's exit status, so it doesn't linger as a zombie" do
        pids = record_spawns
        run_past_timeout
        expect(reaped?(pids.first)).to be true
      end
    end
  end

  describe "#wait_for_exit" do
    # Spawn a command, in a process group of its own
    def spawn(*cmd) = Process.spawn(*cmd, pgroup: true)

    it "returns how the command exited" do
      expect(spawner.wait_for_exit(spawn("sh", "-c", "exit 4"), nil).exitstatus).to eq(4)
    end

    it "waits for part of a second" do
      expect(spawner.wait_for_exit(spawn("sleep", "0.2"), 0.8)).to be_a(Process::Status)
    end

    it "returns nil if the command is still running at the timeout" do
      pid = spawn("sleep", "30")
      expect(spawner.wait_for_exit(pid, 0.1)).to be_nil
    ensure
      Process.kill("KILL", pid)
      Process.wait(pid)
    end

    it "reads the timeout's seconds with to_f, as a Duration has them" do
      pid = spawn("sleep", "30")
      expect(spawner.wait_for_exit(pid, Class.new { def to_f = 0.1 }.new)).to be_nil
    ensure
      Process.kill("KILL", pid)
      Process.wait(pid)
    end

    it "checks again every EXIT_POLL_INTERVAL seconds" do
      allow(Kernel).to(receive(:sleep).and_wrap_original { |sleep, secs| sleep.call(secs) })
      spawner.wait_for_exit(spawn("sleep", "0.2"), nil)
      expect(Kernel).to have_received(:sleep).with(described_class::EXIT_POLL_INTERVAL).at_least(:once)
    end

    it "checks every twentieth of a second" do
      expect(described_class::EXIT_POLL_INTERVAL).to eq(0.05)
    end

    context "with a clock it can set" do
      let(:pid) { spawn("sleep", "30") }

      before do
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0, 11.0, 12.0)
        allow(Kernel).to receive(:sleep)
      end

      after do
        Process.kill("KILL", pid)
        Process.wait(pid)
      end

      it "stops waiting once the timeout has passed, not after" do
        spawner.wait_for_exit(pid, 1)
        expect(Kernel).not_to have_received(:sleep)
      end

      it "returns nil then" do
        expect(spawner.wait_for_exit(pid, 1)).to be_nil
      end
    end
  end

  describe "#kill_spawned_after" do
    let(:pid) { Process.spawn("sleep", "30", pgroup: true) }

    it "kills the command's process group, and raises" do
      expect { spawner.kill_spawned_after(pid, 1, "cmd") }
        .to raise_error(Timeout::Error, "cmd took longer than 1 seconds")
    end

    it "collects the command's exit status" do
      spawner.kill_spawned_after(pid, 1, "cmd")
    rescue Timeout::Error
      expect(reaped?(pid)).to be true
    end

    it "waits for the command, not for any child" do
      allow(Process).to receive(:wait).and_call_original
      spawner.kill_spawned_after(pid, 1, "cmd")
    rescue Timeout::Error
      expect(Process).to have_received(:wait).with(pid)
    end

    it "raises even when the command was collected already" do
      pid = Process.spawn("true", pgroup: true)
      Process.wait(pid)
      expect { spawner.kill_spawned_after(pid, 1, "cmd") }.to raise_error(Timeout::Error)
    end
  end

  describe "#kill_group_after" do
    before { allow(Process).to receive(:kill) }

    it "raises" do
      expect { spawner.kill_group_after(123, 2, "cmd") }
        .to raise_error(Timeout::Error, "cmd took longer than 2 seconds")
    end

    it "kills the process group that the child leads" do
      spawner.kill_group_after(123, 2, "cmd")
    rescue Timeout::Error
      expect(Process).to have_received(:kill).with("KILL", -123)
    end

    it "raises even if the group is gone" do
      allow(Process).to receive(:kill).with("KILL", -123).and_raise(Errno::ESRCH)
      expect { spawner.kill_group_after(123, 2, "cmd") }
        .to raise_error(Timeout::Error, "cmd took longer than 2 seconds")
    end
  end

  describe "#monotonic_now" do
    it "is the monotonic clock's seconds, as a Float" do
      expect(spawner.monotonic_now).to be_within(1).of(Process.clock_gettime(Process::CLOCK_MONOTONIC))
    end

    it "has fractions of a second" do
      expect(spawner.monotonic_now).to be_a(Float)
    end
  end

  describe "#read_in_background" do
    it "returns a thread whose value is what the pipe had" do
      reader, writer = IO.pipe
      writer.write("hello")
      writer.close
      expect(spawner.read_in_background(reader).value).to eq("hello")
    end

    it "gives an empty String when the pipe is closed while it reads" do
      reader, _writer = IO.pipe
      thread = spawner.read_in_background(reader)
      Timeout.timeout(5) { sleep 0.01 until thread.status == "sleep" }
      reader.close
      expect(thread.value).to eq("")
    end
  end
end
