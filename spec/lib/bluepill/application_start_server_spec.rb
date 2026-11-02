# frozen_string_literal: true

require "tmpdir"

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger, crit: nil) }
  let(:base_dir) { Dir.mktmpdir }
  let(:app) { described_class.new("test", base_dir:) }
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

  # An error whose class has no name
  def anonymous_error(message) = Class.new(StandardError) { define_method(:message) { message } }

  def pid_file = File.join(base_dir, "pids", "test.pid")

  # Stub and record what starting the server calls
  def stub_startup
    app.groups = {"web" => group}
    write_previous_pid
    record(Bluepill::System, :pid_alive?, false)
    record_startup_steps
    allow(Signal).to receive(:trap) { |signal| calls << [:trap, signal] }
    stub_listener_and_socket
    stop_after_first_tick
  end

  # Write a previous bluepill's pid file, which kill_previous_bluepill reads
  def write_previous_pid
    FileUtils.mkdir_p(File.dirname(pid_file))
    File.write(pid_file, "4321")
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

    # Raise error from opening the socket, after the other startup steps,
    # which are stubbed
    def fail_startup(error)
      stub_startup
      allow(Bluepill::Socket).to receive(:server).and_raise(error)
    end

    # Load the app, and return the Bluepill::Error it raises
    def load_error
      app.load
    rescue Bluepill::Error => e
      e
    end

    # An error with a backtrace of two lines
    def boom = RuntimeError.new("boom").tap { |error| error.set_backtrace(["a.rb:1", "b.rb:2"]) }

    it "raises a StartupError when the server fails to start" do
      fail_startup(boom)
      expect(load_error).to have_attributes(
        class: Bluepill::StartupError,
        message: "Failed to start bluepill:\nRuntimeError `boom`\na.rb:1\nb.rb:2"
      )
    end

    it "logs the error and its backtrace at crit, since the daemon's stderr is /dev/null" do
      fail_startup(boom)
      load_error
      [["Bluepill stopped: RuntimeError `boom`"], ["a.rb:1"], ["b.rb:2"]].each do |args|
        expect(logger).to have_received(:crit).with(*args).ordered
      end
    end

    context "with a Bluepill::Error" do
      def already_running = @already_running ||= Bluepill::AlreadyRunningError.new("Server is already running!")

      before { fail_startup(already_running) }

      it "raises it as it is" do
        expect(load_error).to be(already_running)
      end

      it "logs it at crit" do
        load_error
        message = "Bluepill stopped: Bluepill::AlreadyRunningError `Server is already running!`"
        expect(logger).to have_received(:crit).with(message)
      end
    end

    it "reports the message of an error from an anonymous class" do
      fail_startup(anonymous_error("boom"))
      expect(load_error.message).to match(/^ `boom`$/)
    end

    it "logs the message of an error from an anonymous class" do
      fail_startup(anonymous_error("boom"))
      load_error
      expect(logger).to have_received(:crit).with(/\ABluepill stopped: #<Class:0x\h+> `boom`\z/)
    end

    it "lets a signal's exception through" do
      fail_startup(SignalException.new("TERM"))
      expect { app.load }.to raise_error(SignalException)
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
      expect(calls).to eq(startup_calls - [[:setpgid, 0, 0]])
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
      let(:app) { described_class.new("test", base_dir:, foreground: true) }

      it "leads a process group of its own instead of daemonizing" do
        start_server
        expect(calls).to eq(startup_calls - [[:daemonize]])
      end

      it "ignores being unable to become a process group leader" do
        allow(::Process).to receive(:setpgid).and_raise(Errno::EPERM)
        start_server
        expect(Bluepill::System).to have_received(:reset_data)
      end
    end

    it "creates the pids dir first" do
      allow(FileUtils).to receive(:mkdir_p) { |dir| calls << [:mkdir_p, dir] }
      allow(FileUtils).to receive(:chmod)
      start_server
      expect(calls.first).to eq([:mkdir_p, File.join(base_dir, "pids", "test")])
    end
  end
end
