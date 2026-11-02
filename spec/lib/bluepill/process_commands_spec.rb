# frozen_string_literal: true

require_relative "../../support/process_context"

describe Bluepill::Process do
  include_context "with a process"

  describe "#start_process" do
    before { process.start_command = "/etc/init.d/script start" }

    context "with the start command" do
      before do
        allow(Timeout).to receive(:timeout).and_call_original
        process.start_process
      end

      it "logs the start command" do
        expect(logger).to have_received(:warning).with("Executing start command: /etc/init.d/script start")
      end

      it "runs the start command with the process options" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("/etc/init.d/script start", having_attributes(**process.command_options.to_h))
      end

      it "gives the start command start_grace_time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end

      it "skips ticks for start_grace_time" do
        expect(process.skip_ticks_until).to eq now + 3
      end
    end

    it "dispatches on_start_timeout when the start command takes too long" do
      process.on_start_timeout = :unmonitor
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.start_process
      expect(dispatched_events).to eq [[:unmonitor, nil]]
    end

    it "runs the pre start command first" do
      process.pre_start_command = "prepare"
      calls = record_calls
      process.start_process
      expect(calls).to eq [:cleanup, "prepare", "/etc/init.d/script start"]
    end

    it "warns on a non-zero exit code" do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(Bluepill::System::CommandResult.new(exit_code: 1))
      warnings = record_log(:warning)
      process.start_process
      expect(warnings).to include("Start command execution returned non-zero exit code:", {exit_code: 1, stdout: "", stderr: ""}.inspect)
    end

    it "warns when a signal killed the command" do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(Bluepill::System::CommandResult.new(exit_code: nil))
      warnings = record_log(:warning)
      process.start_process
      expect(warnings).to include("Start command execution returned non-zero exit code:", {exit_code: nil, stdout: "", stderr: ""}.inspect)
    end

    context "with a stop signal thread left from an earlier stop" do
      let(:stop_thread) { Thread.new { sleep } }

      before do
        process.instance_variable_get(:@threads) << stop_thread
        process.start_process
      end

      it "kills the thread" do
        stop_thread.join(1)
        expect(stop_thread).not_to be_alive
      end

      it "forgets the thread" do
        expect(process.instance_variable_get(:@threads)).to be_empty
      end
    end

    context "when daemonizing" do
      before do
        process.daemonize = true
        allow(Bluepill::System).to receive(:daemonize).and_return(99)
      end

      it "kills what earlier runs left" do
        process.start_process
        expect(journal).to have_received(:kill_all)
      end

      it "daemonizes the start command with the process options, pid file and logger" do
        process.pid_file = "/var/run/proc.pid"
        process.start_process
        expect(Bluepill::System).to have_received(:daemonize)
          .with("/etc/init.d/script start", having_attributes(**process.command_options.to_h), pid_file: "/var/run/proc.pid", logger: logger)
      end

      it "journals the daemon pid" do
        process.start_process
        expect(journal).to have_received(:append).with(99)
      end

      it "journals children pids when monitoring children" do
        process.monitor_children = true
        process.children << instance_double(described_class, "child", actual_pid: 100)
        journaled = record_journal
        process.start_process
        expect(journaled).to eq [99, 100]
      end

      it "does not journal when daemonizing fails" do
        allow(Bluepill::System).to receive(:daemonize).and_return(nil)
        process.start_process
        expect(journal).not_to have_received(:append)
      end
    end
  end

  describe "#pre_start_process" do
    it "does nothing without a pre start command" do
      process.pre_start_process
      expect(Bluepill::System).not_to have_received(:execute_blocking)
    end

    it "logs nothing without a pre start command" do
      process.pre_start_process
      expect(logger).not_to have_received(:err)
    end

    context "with a pre start command" do
      before { process.pre_start_command = "prepare {{PID}}" }

      it "logs that it runs it, with no pid" do
        process.pre_start_process
        expect(logger).to have_received(:info).with("Executing pre start command: prepare ")
      end

      it "runs it as a hook, with the process options and hook_timeout" do
        process.pre_start_process
        expect(Bluepill::System).to have_received(:execute_blocking)
          .with("prepare ", having_attributes(**process.command_options.to_h, environment: {}, timeout: 30))
      end

      it "logs one that runs longer than hook_timeout, and returns" do
        allow(Bluepill::System).to receive(:execute_blocking).and_raise(Timeout::Error)
        process.pre_start_process
        expect(logger).to have_received(:warning).with("Pre start command took longer than 30 seconds: prepare {{PID}}")
      end

      it "logs one that fails, and returns" do
        allow(Bluepill::System).to receive(:execute_blocking).and_raise(Errno::ENOENT)
        process.pre_start_process
        expect(logger).to have_received(:err).with("Pre start command failed: No such file or directory")
      end

      it "warns on a non-zero exit code" do
        allow(Bluepill::System).to receive(:execute_blocking).and_return(Bluepill::System::CommandResult.new(exit_code: 2))
        process.pre_start_process
        expect(logger).to have_received(:warning).with("Pre start command execution returned non-zero exit code:")
      end
    end
  end

  describe "#stop_process" do
    before { process.actual_pid = 5 }

    context "with a stop command" do
      before do
        process.stop_command = "/etc/init.d/script stop"
        allow(Timeout).to receive(:timeout).and_call_original
        process.stop_process
      end

      it "runs the stop command with the process options" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("/etc/init.d/script stop", having_attributes(**process.command_options.to_h))
      end

      it "gives the stop command stop_grace_time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end
    end

    it "dispatches stop when the stop command takes too long" do
      process.stop_command = "/etc/init.d/script stop"
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.stop_process
      expect(dispatched_events).to eq [[:stop, nil]]
    end

    context "with a stop command that fails" do
      let(:warnings) { record_log(:warning) }

      before do
        process.stop_command = "kill {{PID}}; wait {{PID}}"
        process.pid_file = "some.pid"
        allow(Bluepill::System).to receive(:execute_blocking).and_return(Bluepill::System::CommandResult.new(exit_code: 1))
        allow(Bluepill::System).to receive(:get_children)
        warnings
        process.stop_process
      end

      it "logs the command with the pid, and warns of the exit code" do
        expect(warnings.first(2)).to eq ["Executing stop command: kill 5; wait 5", "Stop command execution returned non-zero exit code:"]
      end

      it "looks for no children when not monitoring them" do
        expect(Bluepill::System).not_to have_received(:get_children)
      end

      it "cleans up the journal" do
        expect(journal).to have_received(:kill_all)
      end

      it "deletes the pid file" do
        expect(Bluepill::System).to have_received(:delete_if_exists).with("some.pid")
      end

      it "substitutes the pid" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("kill 5; wait 5", anything)
      end
    end

    context "when monitoring children" do
      before { process.monitor_children = true }

      it "journals children" do
        allow(Bluepill::System).to receive(:get_children).with(5).and_return([6, 7])
        journaled = record_journal
        process.stop_process
        expect(journaled).to eq [6, 7]
      end

      it "journals no children when stopped before it has a pid" do
        process.clear_pid
        allow(Bluepill::System).to receive(:ps_axu).and_return(0 => %w[PID PPID %CPU RSS ELAPSED COMMAND])
        journaled = record_journal
        process.stop_process
        expect(journaled).to be_empty
      end
    end

    context "without a stop command or stop signals" do
      before { process.stop_process }

      it "logs that it sends TERM" do
        expect(logger).to have_received(:warning).with("Executing default stop command. Sending TERM signal to 5")
      end

      it "sends TERM" do
        expect(::Process).to have_received(:kill).with("TERM", 5)
      end

      it "deletes the pid file" do
        expect(Bluepill::System).to have_received(:delete_if_exists).with(nil)
      end

      it "skips ticks for stop_grace_time" do
        expect(process.skip_ticks_until).to eq now + 3
      end
    end

    context "with stop signals" do
      # The seconds the process sleeps for, between stop signals and while it
      # waits for the process to exit
      let(:sleeps) { [] }

      before { allow(Kernel).to receive(:sleep) { |seconds| sleeps << seconds } }

      def run_stop_signals(signals, grace_time = 3)
        process.stop_signals = signals
        process.stop_grace_time = grace_time
        process.stop_process
        process.instance_variable_get(:@threads).each(&:join)
      end

      it "sends a single signal, and waits for it" do
        calls = record_calls
        run_stop_signals([:quit])
        expect(calls).to eq [["QUIT", 5], [0, 5], :cleanup, :unlink]
      end

      it "logs that it sends stop signals" do
        run_stop_signals([:quit])
        expect(logger).to have_received(:warning).with("Sending stop signals to 5")
      end

      it "cleans up the journal of the process" do
        run_stop_signals([:quit])
        expect(journal).to have_received(:kill_all)
      end

      it "sends each signal while the process is alive" do
        calls = record_calls
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(calls).to eq [["QUIT", 5], [0, 5], ["TERM", 5], [0, 5], ["KILL", 5], :cleanup, :unlink]
      end

      it "logs each signal" do
        infos = record_log(:info)
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(infos).to eq ["Sending signal quit to 5", "Sending signal term to 5", "Sending signal kill to 5"]
      end

      it "logs each delay" do
        debugs = record_log(:debug)
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(debugs).to eq ["Sleeping for 2 seconds", "Sleeping for 3 seconds"]
      end

      it "waits for each delay" do
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(sleeps).to eq [2, 3]
      end

      it "leaves the stop signals as they were" do
        run_stop_signals([:quit, 2, :term, 3, :kill])
        expect(process.stop_signals.to_a).to eq [:quit, 2, :term, 3, :kill]
      end

      it "stops once the process has terminated" do
        calls = record_calls(0)
        run_stop_signals([:quit, 2, :kill])
        expect(calls).to eq [["QUIT", 5], [0, 5], :cleanup, :unlink]
      end

      it "logs that the process has terminated" do
        record_calls(0)
        run_stop_signals([:quit, 2, :kill])
        expect(logger).to have_received(:debug).with("Process has terminated.")
      end

      it "checks a fractional wait in whole seconds, rounded up" do
        calls = record_calls
        run_stop_signals([:quit], 4.5)
        expect(calls).to eq [["QUIT", 5], [0, 5], [0, 5], [0, 5], :cleanup, :unlink]
      end

      it "rounds a fractional wait up to whole seconds" do
        run_stop_signals([:quit], 4.5)
        expect(sleeps).to eq [1, 1, 1]
      end

      it "waits for the process to exit before cleaning up" do
        calls = record_calls
        run_stop_signals([:quit], 5)
        expect(calls).to eq [["QUIT", 5], [0, 5], [0, 5], [0, 5], :cleanup, :unlink]
      end

      it "waits a second between checks" do
        run_stop_signals([:quit], 5)
        expect(sleeps).to eq [1, 1, 1]
      end

      it "cleans up as soon as the process exits after the last signal" do
        calls = record_calls(2)
        run_stop_signals([:quit, 2, :term], 10)
        expect(calls).to eq [["QUIT", 5], [0, 5], ["TERM", 5], [0, 5], [0, 5], :cleanup, :unlink]
      end

      it "stops waiting as soon as the process exits after the last signal" do
        record_calls(2)
        run_stop_signals([:quit, 2, :term], 10)
        expect(sleeps).to eq [2, 1]
      end
    end
  end

  describe "#restart_process" do
    context "with a restart command" do
      before do
        process.restart_command = "/etc/init.d/script restart"
        allow(Timeout).to receive(:timeout).and_call_original
        process.restart_process
      end

      it "runs the restart command with the process options" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("/etc/init.d/script restart", having_attributes(**process.command_options.to_h))
      end

      it "gives the restart command restart_grace_time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end

      it "skips ticks for restart_grace_time" do
        expect(process.skip_ticks_until).to eq now + 3
      end
    end

    it "dispatches restart when the restart command takes too long" do
      process.restart_command = "/etc/init.d/script restart"
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      process.restart_process
      expect(dispatched_events).to eq [[:restart, nil]]
    end

    context "with a restart command that fails" do
      before do
        process.restart_command = "restart {{PID}}"
        run_process
        allow(Bluepill::System).to receive(:execute_blocking).and_return(Bluepill::System::CommandResult.new(exit_code: 1))
      end

      it "logs the command with the pid, and warns of the exit code" do
        warnings = record_log(:warning)
        process.restart_process
        expect(warnings.first(2)).to eq ["Executing restart command: restart 5", "Restart command execution returned non-zero exit code:"]
      end

      it "substitutes the pid" do
        process.restart_process
        expect(Bluepill::System).to have_received(:execute_blocking).with("restart 5", anything)
      end
    end

    context "without a restart command" do
      before do
        run_process
        process.start_command = "start-cmd"
      end

      it "logs that it stops and starts" do
        process.restart_process
        expect(logger).to have_received(:warning).with("No restart_command specified. Must stop and start to restart")
      end

      it "stops and starts" do
        calls = record_calls
        process.restart_process
        expect(calls).to eq [["TERM", 5], :cleanup, :unlink, :cleanup, "start-cmd"]
      end

      it "waits for the stop signals to finish before starting" do
        # A real delay, shortened, so the stop signals are still running when
        # the restart waits for them. The default stop_grace_time of 3 leaves
        # nothing to wait for after the last signal.
        allow(Kernel).to receive(:sleep) { sleep(0.1) }
        process.stop_signals = [:quit, 1, :kill]
        calls = record_calls
        process.restart_process
        expect(calls).to eq [["QUIT", 5], [0, 5], ["KILL", 5], :cleanup, :unlink, :cleanup, "start-cmd"]
      end
    end
  end

  describe "#clean_threads" do
    let(:thread) { leftover_thread }

    before do
      thread
      process.clean_threads
    end

    it "kills threads" do
      expect(thread).to have_received(:kill)
    end

    it "clears threads" do
      expect(process.instance_variable_get(:@threads)).to be_empty
    end
  end

  describe "#signal_process" do
    before { process.actual_pid = 5 }

    # Send a signal, and return whether signal_process sent it, with the
    # signals and pids it gave ::Process.kill
    def signal_and_kills(code)
      kills = []
      allow(::Process).to receive(:kill) { |*args| kills << args }
      [process.signal_process(code), kills]
    end

    it "upcases string signals" do
      expect(signal_and_kills("hup")).to eq [true, [["HUP", 5]]]
    end

    it "upcases strings of a String subclass" do
      expect(signal_and_kills(Class.new(String).new("hup"))).to eq [true, [["HUP", 5]]]
    end

    it "turns symbol signals into upcased strings" do
      expect(signal_and_kills(:hup)).to eq [true, [["HUP", 5]]]
    end

    it "signals pid 1" do
      process.actual_pid = 1
      expect(signal_and_kills(0)).to eq [true, [[0, 1]]]
    end

    it "passes integer signals through" do
      expect(signal_and_kills(9)).to eq [true, [[9, 5]]]
    end

    context "when the signal fails" do
      before { allow(::Process).to receive(:kill).and_raise(Errno::EPERM) }

      it "returns false" do
        expect(process.signal_process(0)).to be false
      end

      it "logs the failure" do
        process.signal_process(0)
        expect(logger).to have_received(:err).with(/Failed to signal process 5 with code 0/)
      end
    end

    [0, -1].each do |pid|
      it "never signals pid #{pid}" do
        process.instance_variable_set(:@actual_pid, pid)
        expect(signal_and_kills(0)).to eq [false, []]
      end

      it "logs that pid #{pid} is invalid" do
        process.instance_variable_set(:@actual_pid, pid)
        process.signal_process(0)
        expect(logger).to have_received(:err).with("Failed to signal process #{pid} with code 0: invalid pid #{pid}")
      end
    end

    it "returns false, without signaling, when there is no pid" do
      process.instance_variable_set(:@actual_pid, nil)
      expect(signal_and_kills(0)).to eq [false, []]
    end

    it "logs no error when there is no pid" do
      process.instance_variable_set(:@actual_pid, nil)
      process.signal_process(0)
      expect(logger).not_to have_received(:err)
    end
  end

  describe "#with_timeout" do
    let(:block) { proc {} }

    it "returns the result of the block" do
      expect(process.with_timeout(3, :unmonitor) { :done }).to eq :done
    end

    context "when the block times out" do
      let(:errors) { record_log(:err) }

      before do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
        errors
        process.with_timeout(3, :unmonitor, &block)
      end

      it "logs why it might" do
        expect(errors).to eq ["Execution is taking longer than expected.", "Did you forget to tell bluepill to daemonize this process?"]
      end

      it "gives the block its time" do
        expect(Timeout).to have_received(:timeout).with(3)
      end

      it "proceeds to next_state" do
        expect(dispatched_events).to eq [[:unmonitor, nil]]
      end
    end

    it "times out after a fraction of a second" do
      process.with_timeout(0.01, :unmonitor) { Kernel.sleep 1 }
      expect(dispatched_events).to eq [[:unmonitor, nil]]
    end
  end

  describe "#command_options" do
    subject(:process) { described_class.new(:proc_name, [], **options, logger: logger) }

    let(:options) do
      {
        uid: "user",
        gid: "group",
        working_dir: "/work",
        environment: {"A" => "b"},
        pid_file: "proc.pid",
        stdin: "in",
        stdout: "out",
        stderr: "err",
        supplementary_groups: ["extra"]
      }
    end

    it "passes the process settings to the command" do
      expect(process.command_options.to_h).to eq options.except(:pid_file).merge(timeout: nil)
    end
  end

  describe "#run_hook" do
    let(:options) { process.command_options.to_h }

    context "with a pid and an environment" do
      before do
        process.environment = {"A" => "1"}
        process.run_hook("renice 20 {{PID}} {{PID}}", "Post start", 7, "B" => "2")
      end

      it "logs the command with the pid" do
        expect(logger).to have_received(:info).with("Executing post start command: renice 20 7 7")
      end

      it "warns of nothing when the command succeeds" do
        expect(logger).not_to have_received(:warning)
      end

      it "runs the command with the pid, and the process's options and environment" do
        expect(Bluepill::System).to have_received(:execute_blocking)
          .with("renice 20 7 7", having_attributes(**options, environment: {"A" => "1", "B" => "2"}, timeout: 30))
      end
    end

    it "adds nothing to the environment by default" do
      process.run_hook("drain", "Pre stop", 7)
      expect(Bluepill::System).to have_received(:execute_blocking).with("drain", having_attributes(**options, timeout: 30))
    end

    it "runs without an environment of its own" do
      process.environment = nil
      process.run_hook("alert", "Notify", nil, "B" => "2")
      expect(Bluepill::System).to have_received(:execute_blocking).with("alert", having_attributes(environment: {"B" => "2"}))
    end

    it "logs a non-zero exit code" do
      allow(Bluepill::System).to receive(:execute_blocking).and_return(Bluepill::System::CommandResult.new(exit_code: 1))
      process.run_hook("alert", "Notify", 7)
      expect(logger).to have_received(:warning).with("Notify command execution returned non-zero exit code:")
    end

    it "gives the command hook_timeout, and logs one that runs longer" do
      process.hook_timeout = 5
      allow(Bluepill::System).to receive(:execute_blocking).with("drain 7", having_attributes(timeout: 5)).and_raise(Timeout::Error)
      process.run_hook("drain {{PID}}", "Pre stop", 7)
      expect(logger).to have_received(:warning).with("Pre stop command took longer than 5 seconds: drain {{PID}}")
    end

    context "with a command that fails to run" do
      before { allow(Bluepill::System).to receive(:execute_blocking).and_raise(Errno::EAGAIN, "fork") }

      it "does not raise" do
        expect { process.run_hook("cleanup", "Post stop", 7) }.not_to raise_error
      end

      it "logs the failure" do
        process.run_hook("cleanup", "Post stop", 7)
        expect(logger).to have_received(:err).with("Post stop command failed: Resource temporarily unavailable - fork")
      end
    end
  end

  describe "#run_hook_in_background" do
    it "runs the hook in a thread of its own" do
      ran_on = record_command_threads
      thread = process.run_hook_in_background("alert", "Notify", 5, "A" => "1")
      thread.join
      expect(ran_on).to eq [thread]
    end

    it "runs the hook with its pid and environment" do
      process.run_hook_in_background("alert {{PID}}", "Notify", 5, "A" => "1").join
      expect(Bluepill::System).to have_received(:execute_blocking).with("alert 5", having_attributes(environment: {"A" => "1"}))
    end

    it "logs the hook with its description" do
      process.run_hook_in_background("alert {{PID}}", "Notify", 5, "A" => "1").join
      expect(logger).to have_received(:info).with("Executing notify command: alert 5")
    end

    it "adds nothing to the environment by default" do
      process.environment = {"A" => "1"}
      process.run_hook_in_background("renice", "Post start", 5).join
      expect(Bluepill::System).to have_received(:execute_blocking).with("renice", having_attributes(environment: {"A" => "1"}))
    end
  end

  describe "#post_start_process" do
    before do
      process.post_start_command = "renice 20 {{PID}}"
      run_process
    end

    it "does nothing without a post start command" do
      process.post_start_command = nil
      expect(process.post_start_process).to be_nil
    end

    it "runs the post start command with the pid in the background" do
      process.post_start_process.join
      expect(Bluepill::System).to have_received(:execute_blocking).with("renice 20 5", anything)
    end

    it "logs the post start command" do
      process.post_start_process.join
      expect(logger).to have_received(:info).with("Executing post start command: renice 20 5")
    end

    %i[starting restarting].each do |state|
      context "when the process comes up from #{state}" do
        before do
          threads = capture_threads
          process.state = state
          process.tick
          threads.each(&:join)
        end

        it "runs" do
          expect(Bluepill::System).to have_received(:execute_blocking).with("renice 20 5", anything)
        end

        it "is up" do
          expect(process).to be_up
        end
      end
    end

    %i[down up stopping].each do |state|
      it "doesn't run when a process comes back up by itself, or stays up, from #{state}" do
        threads = capture_threads
        process.state = state
        process.tick
        expect(threads).to be_empty
      end
    end
  end

  describe "#pre_stop_process" do
    before { run_process }

    it "runs the pre stop command, and waits for it, before stopping" do
      process.pre_stop_command = "drain {{PID}}"
      calls = record_calls
      process.stop_process
      expect(calls).to eq ["drain 5", ["TERM", 5], :cleanup, :unlink]
    end

    it "runs the pre stop command as Pre stop" do
      process.pre_stop_command = "drain {{PID}}"
      process.stop_process
      expect(logger).to have_received(:info).with("Executing pre stop command: drain 5")
    end

    it "does nothing without a pre stop command" do
      process.stop_process
      expect(Bluepill::System).not_to have_received(:execute_blocking)
    end

    it "logs no failed hook without a pre stop command" do
      process.stop_process
      expect(logger).not_to have_received(:err)
    end
  end

  describe "#post_stop_process" do
    before do
      run_process
      process.post_stop_command = "rm /tmp/{{PID}}.sock"
    end

    it "runs the post stop command after cleaning up" do
      threads = capture_threads
      calls = record_calls
      process.stop_process
      threads.each(&:join)
      expect(calls).to eq [["TERM", 5], :cleanup, :unlink, "rm /tmp/5.sock"]
    end

    it "runs the post stop command in the background" do
      threads = capture_threads
      ran_on = record_command_threads
      process.stop_process
      threads.each(&:join)
      expect(ran_on).to eq threads
    end

    context "when bluepill has forgotten the pid of the process that stopped" do
      before do
        process.post_stop_command = nil
        process.stop_process
        process.clear_pid
        process.post_stop_command = "rm /tmp/{{PID}}.sock"
        process.post_stop_process.join
      end

      it "gives the post stop command that pid" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("rm /tmp/5.sock", anything)
      end

      it "logs the post stop command" do
        expect(logger).to have_received(:info).with("Executing post stop command: rm /tmp/5.sock")
      end
    end

    context "without a post stop command" do
      before { process.post_stop_command = nil }

      it "runs nothing in the background" do
        threads = capture_threads
        process.stop_process
        expect(threads).to be_empty
      end

      it "does nothing" do
        expect(process.post_stop_process).to be_nil
      end
    end
  end

  describe "#notify_transition" do
    let(:transition) { described_class::Transition.new(:up, :restarting) }

    before { process.notify_command = "alert {{PID}}" }

    context "with an app, a group, a pid and a reason" do
      let(:details) do
        {
          "BLUEPILL_APP" => "app",
          "BLUEPILL_GROUP" => "web",
          "BLUEPILL_PROCESS" => "proc_name",
          "BLUEPILL_FROM" => "up",
          "BLUEPILL_TO" => "restarting",
          "BLUEPILL_REASON" => "mem_usage: [1.2GB*]",
          "BLUEPILL_PID" => "5"
        }
      end

      before do
        process.app_name = "app"
        process.group_name = "web"
        run_process
        process.instance_variable_set(:@transition_reason, "mem_usage: [1.2GB*]")
        process.notify_transition(transition).join
      end

      it "runs the notify command in the background, with the details in its environment" do
        expect(Bluepill::System).to have_received(:execute_blocking).with("alert 5", having_attributes(environment: details))
      end

      it "logs the notify command" do
        expect(logger).to have_received(:info).with("Executing notify command: alert 5")
      end
    end

    it "gives the last pid of a process that died, and empty values for what it lacks" do
      run_process
      process.clear_pid
      process.notify_transition(transition).join
      expect(Bluepill::System).to have_received(:execute_blocking)
        .with("alert 5", having_attributes(environment: hash_including("BLUEPILL_APP" => "", "BLUEPILL_GROUP" => "", "BLUEPILL_REASON" => "", "BLUEPILL_PID" => "5")))
    end

    it "gives no pid before the process has one" do
      process.notify_transition(transition).join
      expect(Bluepill::System).to have_received(:execute_blocking).with("alert ", having_attributes(environment: hash_including("BLUEPILL_PID" => "")))
    end

    it "does nothing for a loopback" do
      expect(process.notify_transition(described_class::Transition.new(:up, :up))).to be_nil
    end

    it "does nothing without a notify command" do
      process.notify_command = nil
      expect(process.notify_transition(transition)).to be_nil
    end

    context "when an event changes the state" do
      before do
        threads = capture_threads
        process.state = :up
        process.dispatch!(:stop, "user initiated")
        threads.each(&:join)
      end

      it "runs, with the event's reason" do
        expect(Bluepill::System).to have_received(:execute_blocking).with(
          "alert ",
          having_attributes(environment: hash_including("BLUEPILL_FROM" => "up", "BLUEPILL_TO" => "stopping", "BLUEPILL_REASON" => "user initiated"))
        )
      end

      it "forgets the reason after" do
        expect(process.instance_variable_get(:@transition_reason)).to be_nil
      end
    end

    context "when the transition raises" do
      before do
        process.state = :up
        allow(journal).to receive(:kill_all).and_raise("boom")
      end

      it "raises" do
        expect { process.dispatch!(:stop, "user initiated") }.to raise_error("boom")
      end

      def dispatch_and_rescue
        process.dispatch!(:stop, "user initiated")
      rescue RuntimeError
        nil
      end

      it "forgets the reason even so" do
        dispatch_and_rescue
        expect(process.instance_variable_get(:@transition_reason)).to be_nil
      end
    end
  end
end
