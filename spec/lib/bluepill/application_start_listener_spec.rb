# frozen_string_literal: true

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger) }
  let(:app) { described_class.new("test", base_dir: "/var/bluepill") }

  before do
    allow(logger).to receive(:prefix_with).and_return(logger)
    allow(Bluepill::Logger).to receive(:new).and_return(logger)
    allow(Bluepill::ProcessJournal).to receive(:setup)
    allow(Bluepill::ProcessJournal).to receive(:logger=)
    # Don't trap the specs' own signals
    allow(Signal).to receive(:trap)
    # Don't make /var/bluepill's directories
    allow(FileUtils).to receive_messages(mkdir_p: nil, chmod: nil)
  end

  # An error whose class has no name
  def anonymous_error(message) = Class.new(StandardError) { define_method(:message) { message } }

  def mutex_locked? = app.instance_variable_get(:@mutex).locked?

  describe "start_listener" do
    let(:client) { instance_double(UNIXSocket, readline: "status:web\n", write: nil, close: nil) }
    let(:group) { instance_double(Bluepill::Group, status: []) }
    let(:logged) { [] }

    before do
      app.socket = instance_double(UNIXServer)
      accepting(client)
      allow(client).to receive(:close_on_exec=)
      app.groups = {"web" => group}
      # The listener's thread is its block, which listen calls
      allow(Thread).to receive(:new) { |&block| block }
      allow(logger).to receive(:err) { |line| logged << line }
    end

    # The socket accepts the client, or raises the error, once, and then
    # raises Interrupt, which the listener doesn't rescue, to end its loop
    def accepting(client_or_error)
      accepted = false
      allow(app.socket).to receive(:accept) do
        raise Interrupt if accepted

        accepted = true
        client_or_error.is_a?(Exception) ? raise(client_or_error) : client_or_error
      end
    end

    def listen
      app.send(:start_listener).call
    rescue Interrupt
      nil
    end

    context "with a command" do
      before do
        allow(group).to receive(:status).with(nil).and_return(["web:a"])
        listen
      end

      it "listens in a loop" do
        expect(app.socket).to have_received(:accept).twice
      end

      it "keeps the client from leaking into processes it starts" do
        expect(client).to have_received(:close_on_exec=).with(true)
      end

      it "answers with the marshaled response" do
        expect(client).to have_received(:write).with(Marshal.dump(["web:a"]))
      end

      it "closes the client" do
        expect(client).to have_received(:close)
      end
    end

    it "ignores whitespace around the command" do
      allow(client).to receive(:readline).and_return(" status:web\n")
      listen
      expect(group).to have_received(:status).with(nil)
    end

    it "runs the command while holding the mutex" do
      allow(group).to receive(:status) { mutex_locked? }
      listen
      expect(client).to have_received(:write).with(Marshal.dump(true))
    end

    it "sends a command without a target" do
      allow(client).to receive(:readline).and_return("status:\n")
      listen
      expect(group).to have_received(:status).with(no_args)
    end

    it "keeps the colons in a process name" do
      app.groups = {"jobs" => group}
      allow(client).to receive(:readline).and_return("status:jobs:job_1:IMPORT\n")
      listen
      expect(group).to have_received(:status).with("job_1:IMPORT")
    end

    # The object the listener marshaled for the client
    def answer
      answered = []
      allow(Marshal).to receive(:dump) do |object|
        answered << object
        "answer"
      end
      listen
      expect(client).to have_received(:write).with("answer")
      answered.fetch(0)
    end

    it "answers the version command" do
      allow(client).to receive(:readline).and_return("version\n")
      expect(answer).to eq(Bluepill::Version)
    end

    it "answers the log_file command" do
      app.log_file = "/var/log/app.log"
      allow(client).to receive(:readline).and_return("log_file\n")
      expect(answer).to eq("/var/log/app.log")
    end

    it "answers a method that isn't a command with a NoMethodError" do
      allow(client).to receive(:readline).and_return("add_process:web\n")
      expect(answer).to have_attributes(class: NoMethodError, message: "Unknown command `add_process`")
    end

    it "doesn't run a method that isn't a command" do
      allow(client).to receive(:readline).and_return("instance_eval:groups.clear\n")
      listen
      expect(app.groups).to eq("web" => group)
    end

    it "doesn't run a command's setter" do
      allow(client).to receive(:readline).and_return("log_file=:/tmp/log\n")
      expect([answer.message, app.log_file]).to eq(["Unknown command `log_file=`", nil])
    end

    # The error takes caller's lines, which start at the method that asked
    # for the command, so Ruby 3.1's error_highlight has no line to quote
    it "answers an unknown command with the backtrace of the method that asked for it" do
      allow(client).to receive(:readline).and_return("add_process:web\n")
      expect(answer.backtrace.first).to include("command_result")
    end

    it "answers an empty line with a NoMethodError" do
      allow(client).to receive(:readline).and_return("\n")
      expect(answer).to have_attributes(class: NoMethodError, message: "Unknown command ``")
    end

    it "answers with the error raised by a command" do
      error = RuntimeError.new("boom")
      allow(group).to receive(:status).and_raise(error)
      listen
      expect(client).to have_received(:write).with(Marshal.dump(error))
    end

    context "when handling a client fails" do
      before do
        error = RuntimeError.new("broken pipe")
        error.set_backtrace(["a.rb:1"])
        allow(client).to receive(:write).and_raise(error)
        listen
      end

      it "logs the error and its backtrace" do
        expect(logged).to eq(["Got exception in cmd listener: RuntimeError `broken pipe`", "a.rb:1"])
      end

      it "closes the client" do
        expect(client).to have_received(:close)
      end
    end

    it "logs the message of an error from an anonymous class" do
      allow(client).to receive(:write).and_raise(anonymous_error("broken pipe"))
      listen
      expect(logged.first).to eq("Got exception in cmd listener:  `broken pipe`")
    end

    it "logs an error without a backtrace" do
      error = RuntimeError.new("broken pipe")
      allow(error).to receive(:backtrace).and_return(nil)
      allow(client).to receive(:write).and_raise(error)
      listen
      expect(logged).to eq(["Got exception in cmd listener: RuntimeError `broken pipe`"])
    end

    context "when accepting a client fails" do
      before do
        error = Errno::EMFILE.new
        error.set_backtrace(["a.rb:1"])
        accepting(error)
        listen
      end

      it "keeps listening" do
        expect(app.socket).to have_received(:accept).twice
      end

      it "logs the error and its backtrace" do
        expect(logged).to eq(["Got exception in cmd listener: Errno::EMFILE `#{Errno::EMFILE.new.message}`", "a.rb:1"])
      end
    end

    it "ignores an already closed client" do
      allow(client).to receive(:close).and_raise(IOError)
      expect { listen }.not_to raise_error
    end

    it "kills the previous listener" do
      thread = instance_double(Thread, kill: nil)
      allow(Thread).to receive(:new).and_return(thread)
      app.send(:start_listener)
      app.send(:start_listener)
      expect(thread).to have_received(:kill).once
    end
  end
end
