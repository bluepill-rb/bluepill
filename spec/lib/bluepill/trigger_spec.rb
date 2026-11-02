# frozen_string_literal: true

describe Bluepill::Trigger do
  subject(:trigger) { described_class.new(process, logger: logger) }

  # What the process is told to dispatch and what the logger logs, in order
  let(:calls) { [] }
  let(:process) { record(instance_double(Bluepill::Process), :dispatch!) }
  let(:logger) { record(instance_double(Bluepill::Logger), :info, :err) }

  # Record each method's calls in calls, as [method, *args]
  def record(double, *methods)
    methods.each do |method|
      allow(double).to receive(method) { |*args| calls << [method, *args] }
    end
    double
  end

  describe ".[]" do
    it "looks up registered triggers by name" do
      expect(described_class[:flapping]).to eq(Bluepill::Triggers::Flapping)
    end

    it "returns nil for unknown triggers" do
      expect(described_class[:unknown]).to be_nil
    end
  end

  describe ".inherited" do
    let(:klass) { Class.new }

    before do
      allow(klass).to receive(:name).and_return("Bluepill::Triggers::SpecExample")
      allow(Object).to receive(:inherited).and_call_original
    end

    after do
      described_class.instance_variable_get(:@implementations).delete(:spec_example)
    end

    it "registers subclasses by their underscored name" do
      described_class.send(:inherited, klass)
      expect(described_class[:spec_example]).to equal(klass)
    end

    it "calls the inherited hook of its superclass" do
      described_class.send(:inherited, klass)
      expect(Object).to have_received(:inherited).with(klass)
    end
  end

  it "throws :halt to stop a transition" do
    expect(described_class::HALT).to be(:halt)
  end

  describe "#initialize" do
    it "sets up the trigger" do
      expect([trigger, trigger.send(:mutex)]).to match([have_attributes(process: process, logger: logger, scheduled_events: []), be_a(Mutex)])
    end

    it "can be created without options" do
      expect(described_class.new(process).logger).to be_nil
    end

    it "takes its class's name, without its modules, as its dispatch reason" do
      Bluepill::Triggers::Flapping.new(process, logger: logger).dispatch!(:start)
      expect(calls).to eq([[:dispatch!, :start, "Flapping"]])
    end
  end

  describe "#notify" do
    it "must be implemented by subclasses" do
      expect { trigger.notify(nil) }.to raise_error("Implement in subclass")
    end
  end

  describe "#dispatch!" do
    it "dispatches the event to the process with the trigger name as reason" do
      trigger.dispatch!(:start)
      expect(calls).to eq([[:dispatch!, :start, "Trigger"]])
    end
  end

  describe "#schedule_event" do
    # Wake the thread of a scheduled event until it finishes. It may not be
    # asleep yet, or be done by the time it's woken.
    def finish(thread)
      until thread.join(0.01)
        begin
          thread.wakeup
        rescue ThreadError
          nil
        end
      end
    end

    # The scheduled events after each thread finishes, one at a time
    def events_after_finishing(*threads)
      threads.collect do |thread|
        finish(thread)
        trigger.scheduled_events.dup
      end
    end

    # Hold back recording an event until its thread has dispatched it and
    # is waiting for the lock or done
    def record_after_dispatch
      # The thread that dispatched, once it has
      dispatched = Queue.new
      allow(process).to receive(:dispatch!) { dispatched.push(Thread.current) }
      allow(trigger.scheduled_events).to receive(:push).and_wrap_original do |push, *args|
        wait_while_running(dispatched.pop)
        push.call(*args)
      end
    end

    # Wait until a thread is asleep, waiting for a lock, or done
    def wait_while_running(thread)
      Thread.pass while thread.status == "run"
    end

    # An error to raise while dispatching, with the given backtrace
    def dispatch_error(backtrace)
      error = RuntimeError.new("boom")
      allow(error).to receive(:backtrace).and_return(backtrace)
      allow(process).to receive(:dispatch!).and_raise(error)
      error
    end

    it "sleeps before it dispatches the event" do
      thread = trigger.schedule_event(:start, 60)
      Thread.pass while thread.status == "run"
      calls << thread.status
      finish(thread)
      expect(calls).to eq(["sleep", [:dispatch!, :start, "Trigger"]])
    end

    it "sleeps for a duration in seconds" do
      allow(Kernel).to receive(:sleep)
      trigger.schedule_event(:start, 0.05.seconds).join
      expect(Kernel).to have_received(:sleep).with(0.05)
    end

    it "sleeps for a delay that only converts to a Float, such as a duration" do
      allow(Kernel).to receive(:sleep)
      trigger.schedule_event(:start, Struct.new(:to_f).new(0.05)).join
      expect(Kernel).to have_received(:sleep).with(an_instance_of(Float).and(eq(0.05)))
    end

    it "records the scheduled events in order until each one is dispatched" do
      first = trigger.schedule_event(:start, 60)
      second = trigger.schedule_event(:stop, 60)
      events = [trigger.scheduled_events.dup] + events_after_finishing(first, second)
      expect(events).to eq([[[:start, first], [:stop, second]], [[:stop, second]], []])
    end

    it "removes a dispatched event only after it was recorded" do
      record_after_dispatch
      trigger.schedule_event(:start, 0).join
      expect(trigger.scheduled_events).to eq([])
    end

    it "logs errors without a backtrace" do
      error = dispatch_error(nil)
      trigger.schedule_event(:start, 0).join
      expect(calls).to eq([[:err, error], [:err, ""]])
    end

    it "logs errors raised while dispatching" do
      error = dispatch_error(["line 1", "line 2"])
      trigger.schedule_event(:start, 0).join
      expect(calls).to eq([[:err, error], [:err, "line 1\nline 2"]])
    end
  end

  describe "#reset!" do
    it "cancels all scheduled events while it holds the lock" do
      thread = instance_double(Thread)
      allow(thread).to receive(:kill) { calls << [:kill, trigger.send(:mutex).locked?] }
      trigger.scheduled_events.push([:start, thread])
      trigger.reset!
      expect([calls, trigger.scheduled_events]).to eq([[[:info, "Canceling all scheduled events"], [:kill, true]], []])
    end
  end
end
