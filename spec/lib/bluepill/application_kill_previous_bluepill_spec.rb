# frozen_string_literal: true

require "tmpdir"

describe Bluepill::Application do
  let(:base_dir) { Dir.mktmpdir }
  let(:app) { described_class.new("test", base_dir: base_dir) }

  before do
    logger = instance_double(Bluepill::Logger)
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

  def pid_file = File.join(base_dir, "pids", "test.pid")

  describe "kill_previous_bluepill" do
    let(:calls) { [] }

    def write_pid(pid = "1234") = File.write(pid_file, pid)

    def kill_previous_bluepill = app.send(:kill_previous_bluepill)

    def kill_previous_bluepill_until_exit
      kill_previous_bluepill
    rescue SystemExit
      nil
    end

    # A previous bluepill whose pid is alive, with its signals and sleeps
    # recorded, each with what had been printed by then
    def previous_bluepill_running
      write_pid
      allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true)
      record_signals_and_sleeps
    end

    # Record each signal and sleep, with what had been printed by then
    def record_signals_and_sleeps
      allow(::Process).to receive(:kill) { |signal, pid| calls << [:kill, signal, pid, printed] }
      allow(Kernel).to receive(:sleep) { |seconds| calls << [:sleep, seconds, printed] }
    end

    # What's been printed so far, while an output matcher captures stdout
    def printed = $stdout.string.dup

    def killing = "Killing previous bluepilld[1234]\n"

    # The signals and sleeps of a previous bluepill that's killed, and then
    # waited for that many times
    def killed_and_waited_for(times)
      [[:kill, 0, 1234, ""], [:kill, 2, 1234, killing]] + ([[:sleep, 0.5, killing]] * times)
    end

    before do
      app
      allow(Bluepill::System).to receive(:pid_alive?).and_return(false)
      allow(::Process).to receive(:kill)
    end

    it "does nothing without a pid file" do
      kill_previous_bluepill
      expect(Bluepill::System).not_to have_received(:pid_alive?)
    end

    it "checks whether the previous bluepill is running" do
      write_pid
      kill_previous_bluepill
      expect(Bluepill::System).to have_received(:pid_alive?).with(1234)
    end

    it "does nothing when the previous bluepill is not running" do
      write_pid
      kill_previous_bluepill
      expect(::Process).not_to have_received(:kill)
    end

    it "checks a previous bluepill with pid 1, as in a container" do
      write_pid("1")
      kill_previous_bluepill
      expect(Bluepill::System).to have_received(:pid_alive?).with(1)
    end

    ["", "garbage"].each do |contents|
      context "when the pid file holds #{contents.inspect}" do
        before { write_pid(contents) }

        it "prints nothing, and does not exit" do
          expect { kill_previous_bluepill }.not_to output.to_stdout
        end

        it "does not check a pid" do
          kill_previous_bluepill
          expect(Bluepill::System).not_to have_received(:pid_alive?)
        end

        it "does not signal anything" do
          kill_previous_bluepill
          expect(::Process).not_to have_received(:kill)
        end
      end
    end

    context "when the previous bluepill is running" do
      before { previous_bluepill_running }

      it "interrupts it and waits for it to die" do
        allow(Bluepill::System).to receive(:pid_alive?).with(1234).and_return(true, true, false)
        expect { kill_previous_bluepill }.to output(killing).to_stdout.and change(calls, :dup).to(killed_and_waited_for(2))
      end

      it "exits when it does not die" do
        expect { kill_previous_bluepill }.to exit_with(4).and output("Previous bluepilld[1234] didn't die\n").to_stderr.and output(killing).to_stdout
      end

      it "waits kill_timeout half seconds for it to die" do
        allow($stderr).to receive(:puts)
        expect { kill_previous_bluepill_until_exit }.to output(killing).to_stdout.and change(calls, :dup).to(killed_and_waited_for(10))
      end

      it "exits when it cannot be killed" do
        allow(::Process).to receive(:kill).and_raise(Errno::EPERM)
        expect { kill_previous_bluepill }.to exit_with(4).and output(
          "Encountered error trying to kill previous bluepill:\nErrno::EPERM: #{Errno::EPERM.new.message}\n"
        ).to_stderr
      end
    end

    context "when the previous bluepill has just died" do
      before do
        previous_bluepill_running
        allow(::Process).to receive(:kill) do |signal, pid|
          calls << [:kill, signal, pid]
          raise Errno::ESRCH
        end
      end

      it "says so, and does not exit" do
        expect { kill_previous_bluepill }.to output(
          "Encountered error trying to kill previous bluepill:\nErrno::ESRCH: #{Errno::ESRCH.new.message}\n"
        ).to_stderr
      end

      it "carries on without waiting" do
        allow($stderr).to receive(:puts)
        kill_previous_bluepill
        expect(calls).to eq([[:kill, 0, 1234]])
      end
    end
  end
end
