require "tmpdir"

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger, reopen: nil) }
  let(:base_dir) { Dir.mktmpdir }
  let(:app) { described_class.new("test", base_dir: base_dir) }

  before do
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

  def with_env(name, value)
    original = ENV.fetch(name, nil)
    ENV[name] = value
    yield
  ensure
    ENV[name] = original
  end

  def pids_dir
    File.join(base_dir, "pids", "test")
  end

  describe "#initialize" do
    subject(:app) { described_class.new("test", options) }

    let(:options) { {} }
    let(:traps) { {} }

    before do
      allow(Signal).to receive(:trap) { |signal, &block| traps[signal] = block }
      # Don't make the base dir's directories, which for root is /var/run
      allow(FileUtils).to receive_messages(mkdir_p: nil, chmod: nil)
    end

    context "when euid is not root" do
      before { allow(::Process).to receive(:euid).and_return(1) }

      it "uses ~/.bluepill as the base dir" do
        expect(app.base_dir).to eq(File.join(ENV.fetch("HOME", nil), ".bluepill"))
      end
    end

    context "when euid is root" do
      before { allow(::Process).to receive(:euid).and_return(0) }

      it "uses /var/run/bluepill as the base dir" do
        expect(app.base_dir).to eq("/var/run/bluepill")
      end

      it "does not need HOME" do
        expect(with_env("HOME", nil) { app.base_dir }).to eq("/var/run/bluepill")
      end
    end

    context "without options" do
      subject(:app) { described_class.new("test") }

      before { allow(::Process).to receive(:euid).and_return(0) }

      it "uses the defaults" do
        expect(app).to have_attributes(base_dir: "/var/run/bluepill", foreground?: false)
      end
    end

    context "with a base_dir option" do
      let(:options) { {base_dir: "/var/bluepill"} }

      it "uses it as the base dir" do
        expect(app.base_dir).to eq("/var/bluepill")
      end

      it "gives the process journal the base dir and the app's name" do
        app
        expect(Bluepill::ProcessJournal).to have_received(:setup).with("/var/bluepill", "test")
      end

      it "derives the pid file and pids dir" do
        expect(app).to have_attributes(pid_file: "/var/bluepill/pids/test.pid", pids_dir: "/var/bluepill/pids/test")
      end

      it "defaults the kill timeout and foreground mode" do
        expect(app).to have_attributes(kill_timeout: 10, foreground?: false, groups: {})
      end

      it "traps TERM, INT and HUP" do
        app
        expect(traps.keys).to contain_exactly("TERM", "INT", "HUP")
      end

      it "has a mutex" do
        expect(app.mutex { :result }).to eq(:result)
      end

      it "logs with the application name as prefix" do
        prefixed = instance_double(Bluepill::Logger)
        allow(logger).to receive(:prefix_with).with("test").and_return(prefixed)
        expect(app.logger).to be(prefixed)
      end

      it "logs to the log file, and not to stdout" do
        app
        expect(Bluepill::Logger).to have_received(:new).with(log_file: nil, log_level: nil, stdout: false)
      end

      it "gives the process journal the same logger" do
        app
        expect(Bluepill::ProcessJournal).to have_received(:logger=).with(logger)
      end
    end

    context "when option foreground is false" do
      let(:options) { {base_dir: "/var/bluepill", foreground: false} }

      it { is_expected.not_to be_foreground }
    end

    context "with other options" do
      let(:options) { {base_dir: "/var/bluepill", foreground: true, log_file: "log", log_level: :info, kill_timeout: 3} }

      it "uses them" do
        expect(app).to have_attributes(kill_timeout: 3, log_file: "log", foreground?: true)
      end

      it "logs to the log file at the log level, and to stdout" do
        app
        expect(Bluepill::Logger).to have_received(:new).with(log_file: "log", log_level: :info, stdout: true)
      end
    end

    context "when environment BLUEPILL_BASE_DIR is specified" do
      around { |example| with_env("BLUEPILL_BASE_DIR", "/bluepill") { example.run } }

      it "uses it as the base dir" do
        expect(app.base_dir).to eq("/bluepill")
      end
    end

    context "when environment BLUEPILL_BASE_DIR and option base_dir are specified" do
      let(:options) { {base_dir: "/var/bluepill"} }

      around { |example| with_env("BLUEPILL_BASE_DIR", "/bluepill") { example.run } }

      it "uses the option as the base dir" do
        expect(app.base_dir).to eq("/var/bluepill")
      end
    end
  end

  describe "#initialize without permission to write its files" do
    subject(:app) { described_class.new("test", base_dir: "/var/bluepill", log_file: "/var/log/bluepill.log") }

    def startup_failure(message)
      exit_with(5).and output(
        "Failed to start bluepill: #{message}\n" \
        "The user running bluepill must be able to write to its log_file and base_dir. " \
        "The uid and gid in the config only apply to the processes it monitors.\n"
      ).to_stderr
    end

    it "exits with a clear message when it cannot open the log file" do
      allow(Bluepill::Logger).to receive(:new).and_raise(Errno::EACCES, "/var/log/bluepill.log")
      expect { app }.to startup_failure("Permission denied - /var/log/bluepill.log")
    end

    it "exits with a clear message when it cannot create the pids dir" do
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, "/var/bluepill/pids/test")
      expect { app }.to startup_failure("Permission denied - /var/bluepill/pids/test")
    end
  end

  describe "pids dir" do
    it "is created" do
      app
      expect(File).to be_directory(pids_dir)
    end

    it "is created writable for everybody" do
      app
      expect(File.stat(pids_dir).mode & 0o777).to eq(0o777)
    end

    it "is made writable for everybody when it already exists" do
      FileUtils.mkdir_p(pids_dir)
      FileUtils.chmod(0o700, pids_dir)
      app
      expect(File.stat(pids_dir).mode & 0o777).to eq(0o777)
    end
  end

  describe "signal traps" do
    let(:traps) { {} }

    before do
      allow(Signal).to receive(:trap) { |signal, &block| traps[signal] = block }
      allow($stdout).to receive(:puts)
      allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks)
      allow(Bluepill::System).to receive(:delete_if_exists)
      # Creating the app traps the signals
      app
    end

    %w[TERM INT].each do |signal|
      it "says it terminates on #{signal}" do
        expect { traps[signal].call(Signal.list.fetch(signal)) }.to output("Terminating...\n").to_stdout
      end

      it "clears the journal locks on #{signal}" do
        traps[signal].call(Signal.list.fetch(signal))
        expect(Bluepill::ProcessJournal).to have_received(:clear_all_atomic_fs_locks)
      end

      it "deletes the pid file on #{signal}" do
        traps[signal].call(Signal.list.fetch(signal))
        expect(Bluepill::System).to have_received(:delete_if_exists).with(app.pid_file)
      end

      it "stops running on #{signal}" do
        traps[signal].call(Signal.list.fetch(signal))
        expect(app.instance_variable_get(:@running)).to be false
      end
    end

    it "reopens the log on HUP" do
      traps["HUP"].call
      expect(logger).to have_received(:reopen)
    end

    it "ignores HUP without a logger" do
      app.logger = nil
      expect { traps["HUP"].call }.not_to raise_error
    end
  end

  describe "DAEMON_COMMANDS" do
    it "is the commands that the CLI sends" do
      expect(described_class::DAEMON_COMMANDS).to eq([:start, :stop, :restart, :unmonitor, :status, :version, :log_file])
    end

    it "is frozen" do
      expect(described_class::DAEMON_COMMANDS).to be_frozen
    end
  end

  describe "#mutex" do
    it "runs the block synchronized" do
      expect(app.mutex { :result }).to eq(:result)
    end
  end

  describe "#version" do
    it "is the bluepill version" do
      expect(app.version).to eq(Bluepill::Version)
    end
  end

  describe "#add_process" do
    let(:process) { instance_double(Bluepill::Process, :app_name= => nil, :group_name= => nil) }
    let(:group) { instance_double(Bluepill::Group) }

    before { allow(group).to receive(:add_process) }

    context "with a group name" do
      before do
        group_logger = instance_double(Bluepill::Logger)
        allow(logger).to receive(:prefix_with).with("web").and_return(group_logger)
        allow(Bluepill::Group).to receive(:new).with("web", logger: group_logger).and_return(group)
        app.add_process(process, :web)
      end

      it "adds a new group named after the group name" do
        expect(app.groups).to eq("web" => group)
      end

      it "adds the process to the group" do
        expect(group).to have_received(:add_process).with(process)
      end

      it "tells the process its app's name, for notify_command" do
        expect(process).to have_received(:app_name=).with("test")
      end

      it "tells the process its group's name, for notify_command" do
        expect(process).to have_received(:group_name=).with("web")
      end
    end

    context "without a group name" do
      before do
        allow(Bluepill::Group).to receive(:new).with(nil, logger: logger).and_return(group)
        app.add_process(process)
        app.add_process(process)
      end

      it "adds processes to the nil group" do
        expect(app.groups).to eq(nil => group)
      end

      it "creates the nil group once" do
        expect(Bluepill::Group).to have_received(:new).once
      end

      it "adds each process to the nil group" do
        expect(group).to have_received(:add_process).with(process).twice
      end
    end
  end
end
