# frozen_string_literal: true

require_relative "../../support/process_context"

describe Bluepill::Process do
  include_context "with a process"

  describe "#process_running?" do
    before { process.actual_pid = 5 }

    it "is true, and stays true, for a running process" do
      expect(Array.new(2) { process.process_running? }).to eq [true, true]
    end

    it "memoizes a running result" do
      2.times { process.process_running? }
      expect(::Process).to have_received(:kill).once.with(0, 5)
    end

    it "keeps the pid of a running process" do
      process.process_running?
      expect(process.actual_pid).to eq 5
    end

    it "rechecks when forced" do
      process.process_running?
      process.process_running?(true)
      expect(::Process).to have_received(:kill).twice.with(0, 5)
    end

    context "when not running" do
      before { allow(::Process).to receive(:kill).with(0, 5).and_raise(Errno::ESRCH) }

      it "is false" do
        expect(process.process_running?).to be false
      end

      it "clears the pid" do
        process.process_running?
        expect(process.instance_variable_get(:@actual_pid)).to be_nil
      end
    end
  end

  describe "#actual_pid" do
    it "uses the pid command when configured" do
      process.pid_command = "echo 123"
      expect(process.actual_pid).to eq 123
    end

    it "returns nil when the pid command prints 0" do
      process.pid_command = "echo 0"
      expect(process.actual_pid).to be_nil
    end

    it "returns nil when the pid command output is not a number" do
      process.pid_command = "echo oops"
      expect(process.actual_pid).to be_nil
    end

    it "returns nil when the pid command output only starts with a number" do
      process.pid_command = "echo 12 oops"
      expect(process.actual_pid).to be_nil
    end

    it "ignores whitespace and leading zeros around the pid command output" do
      process.pid_command = "echo '  0123'"
      expect(process.actual_pid).to eq 123
    end

    it "is nil without a pid file" do
      expect(process.actual_pid).to be_nil
    end

    context "with a pid file" do
      let(:dir) { Dir.mktmpdir }

      before { process.pid_file = File.join(dir, "proc.pid") }

      after { FileUtils.remove_entry(dir) }

      # Write each content to the pid file in turn, and read the pid after
      # each
      def read_pids(*contents)
        contents.collect do |content|
          File.write(process.pid_file, content)
          process.actual_pid
        end
      end

      it "reads the pid and caches it" do
        expect(read_pids("77\n", "78\n")).to eq [77, 77]
      end

      it "deletes the pid file when it cleans up after a stop" do
        allow(Bluepill::System).to receive(:delete_if_exists).and_call_original
        read_pids("77\n")
        process.cleanup_process
        expect(File.exist?(process.pid_file)).to be false
      end

      it "forgets the cached pid when it cleans up after a stop" do
        allow(Bluepill::System).to receive(:delete_if_exists).and_call_original
        before_cleanup = read_pids("77\n")
        process.cleanup_process
        expect(before_cleanup + read_pids("78\n")).to eq [77, 78]
      end

      it "rereads the pid when not caching" do
        process.cache_actual_pid = false
        expect(read_pids("77\n", "78\n")).to eq [77, 78]
      end

      it "is nil for an empty pid file" do
        File.write(process.pid_file, "")
        expect(process.actual_pid).to be_nil
      end

      it "is nil for a pid file that does not hold a positive pid" do
        process.cache_actual_pid = false
        expect(read_pids("0\n", "\n", "garbage", "-5")).to eq [nil, nil, nil, nil]
      end

      it "is not running for a pid file that holds 0" do
        File.write(process.pid_file, "0\n")
        allow(::Process).to receive(:kill).and_call_original
        expect(process.process_running?(true)).to be false
      end

      it "reads pid 1" do
        File.write(process.pid_file, "1\n")
        expect(process.actual_pid).to eq 1
      end

      it "is nil when the pid file does not exist" do
        expect(process.actual_pid).to be_nil
      end

      it "warns when the pid file does not exist" do
        process.actual_pid
        expect(logger).to have_received(:warning).with("pid_file #{process.pid_file} does not exist or cannot be read")
      end
    end
  end

  describe "#actual_pid=" do
    before { process.actual_pid = 12 }

    it "journals the pid" do
      expect(Bluepill::ProcessJournal).to have_received(:append_pid_to_journal).with(:proc_name, 12)
    end

    it "sets the pid" do
      expect(process.actual_pid).to eq 12
    end
  end

  describe "#clear_pid" do
    before do
      process.actual_pid = 5
      process.clear_pid
      process.clear_pid
    end

    it "forgets the pid" do
      expect(process.instance_variable_get(:@actual_pid)).to be_nil
    end

    it "keeps the last pid for notify_command" do
      expect(process.instance_variable_get(:@last_pid)).to eq 5
    end
  end
end
