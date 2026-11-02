# frozen_string_literal: true

require "tmpdir"

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger, crit: nil) }
  let(:base_dir) { Dir.mktmpdir }
  let(:app) { described_class.new("test", base_dir: base_dir) }
  let(:group) { instance_double(Bluepill::Group) }
  let(:calls) { [] }

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

  # An error whose class has no name
  def anonymous_error(message)
    Class.new(StandardError) { define_method(:message) { message } }
  end

  def pid_file
    File.join(base_dir, "pids", "test.pid")
  end

  # Stub and record what starting the server calls
  def stub_startup
    app.groups = {"web" => group}
    # A previous bluepill's pid file, which kill_previous_bluepill reads
    File.write(pid_file, "4321")
    record(Bluepill::System, :pid_alive?, false)
    record_startup_steps
    # After creating the app, which traps signals too
    allow(Signal).to receive(:trap) { |signal| calls << [:trap, signal] }
    stub_listener_and_socket
    stop_after_first_tick
  end

  # Record the steps of starting the server that return nothing
  def record_startup_steps
    [
      [Bluepill::ProcessJournal, :clear_all_atomic_fs_locks], [::Process, :setpgid], [Bluepill::Daemonize, :daemonize],
      [logger, :reopen], [group, :determine_initial_state], [Bluepill::System, :reset_data], [group, :tick]
    ].each { |object, method| record(object, method) }
  end

  # Record the listener and the socket, without starting or opening them
  def stub_listener_and_socket
    # Don't run the listener
    allow(Thread).to receive(:new) { calls << [:thread] }
    allow(Bluepill::Socket).to receive(:server) do |*args|
      calls << [:server, *args]
      instance_double(UNIXServer)
    end
  end

  # End the run loop after its first tick
  def stop_after_first_tick
    allow(Kernel).to receive(:sleep) do |seconds|
      calls << [:sleep, seconds]
      raise Interrupt
    end
  end

  # Record a call to a method, and return result
  def record(object, method, result = nil)
    allow(object).to receive(method) do |*args|
      calls << [method, *args]
      result
    end
  end

  # Start the server until its run loop sleeps, which raises Interrupt
  def start_server
    app.send(:start_server)
  rescue Interrupt
    nil
  end

  describe "#load" do
    def load_app
      app.load
    rescue Interrupt
      nil
    end

    it "starts the server" do
      stub_startup
      load_app
      expect(Bluepill::Socket).to have_received(:server)
    end

    it "exits when the server fails to start" do
      error = RuntimeError.new("boom")
      error.set_backtrace(["a.rb:1"])
      allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks).and_raise(error)
      expect { app.load }.to exit_with(5).and output("Failed to start bluepill:\nRuntimeError `boom`\na.rb:1\n").to_stderr
    end

    # Load the app with a startup that raises error, past its exit and quietly
    def fail_load(error)
      allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks).and_raise(error)
      allow($stderr).to receive(:puts)
      app.load
    rescue SystemExit
      nil
    end

    it "logs the error and its backtrace at crit, since the daemon's stderr is /dev/null" do
      fail_load(RuntimeError.new("boom").tap { |e| e.set_backtrace(["a.rb:1", "b.rb:2"]) })
      [["Bluepill stopped: RuntimeError `boom`"], ["a.rb:1"], ["b.rb:2"]].each do |args|
        expect(logger).to have_received(:crit).with(*args).ordered
      end
    end

    it "reports the message of an error from an anonymous class" do
      allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks).and_raise(anonymous_error("boom"))
      expect { app.load }.to exit_with(5).and output(/^ `boom`$/).to_stderr
    end
  end

  describe "start_server" do
    around do |example|
      program_name = $0
      begin
        example.run
      ensure
        $0 = program_name
      end
    end

    before { stub_startup }

    def startup_calls
      [
        [:pid_alive?, 4321], [:clear_all_atomic_fs_locks], [:setpgid, 0, 0], [:daemonize],
        [:trap, "TERM"], [:trap, "INT"], [:trap, "HUP"], [:reopen], [:determine_initial_state],
        [:server, base_dir, "test"], [:thread], [:reset_data], [:tick], [:sleep, 1]
      ]
    end

    it "daemonizes and runs the application" do
      start_server
      expect(calls).to eq(startup_calls)
    end

    it "names its process after the application" do
      start_server
      expect($0).to eq("bluepilld: test")
    end

    it "writes its pid file" do
      start_server
      expect(File.read(pid_file)).to eq(::Process.pid.to_s)
    end

    it "keeps the socket" do
      socket = instance_double(UNIXServer)
      allow(Bluepill::Socket).to receive(:server).and_return(socket)
      start_server
      expect(app.socket).to eq(socket)
    end

    it "writes the pid as a string with File.write" do
      allow(File).to receive(:write).and_call_original
      start_server
      expect(File).to have_received(:write).with(pid_file, ::Process.pid.to_s)
    end

    context "when in the foreground" do
      let(:app) { described_class.new("test", base_dir: base_dir, foreground: true) }

      it "does not daemonize, or trap signals again" do
        start_server
        expect(calls).to eq(startup_calls - [[:daemonize], [:trap, "TERM"], [:trap, "INT"], [:trap, "HUP"]])
      end
    end

    it "ignores being unable to become a process group leader" do
      allow(::Process).to receive(:setpgid).and_raise(Errno::EPERM)
      start_server
      expect(Bluepill::System).to have_received(:reset_data)
    end
  end
end
