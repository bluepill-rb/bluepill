describe Bluepill::Triggers::Flapping do
  # What the trigger logs, in order
  let(:calls) { [] }
  # The events the trigger's threads dispatch to the process, each with
  # how long its thread slept first
  let(:dispatched) { [] }
  let(:process) { instance_double(Bluepill::Process) }
  let(:logger) { record(instance_double(Bluepill::Logger), :info) }

  # Record each method's calls in calls, as [method, *args]
  def record(double, *methods)
    methods.each do |method|
      allow(double).to receive(method) { |*args| calls << [method, *args] }
    end
    double
  end

  # Record each event the trigger's threads dispatch, with how long its
  # thread slept first. Each thread keeps that in a thread variable, and
  # the shared array is written under a lock, since on JRuby the threads
  # run at once.
  def record_dispatches
    lock = Mutex.new
    allow(Kernel).to receive(:sleep) { |seconds| Thread.current[:bluepill_slept] = seconds }
    allow(process).to receive(:dispatch!) do |event, reason|
      lock.synchronize { dispatched << [event, reason, Thread.current[:bluepill_slept]] }
    end
  end

  def flapping(options = {})
    described_class.new(process, {logger: logger}.merge(options))
  end

  # Wait for the events the trigger has scheduled to dispatch, so its
  # threads don't outlast the example and its doubles
  def settle(trigger)
    trigger.send(:mutex).synchronize { trigger.scheduled_events.collect(&:last) }.each(&:join)
  end

  # Notify the trigger, and wait for the events it schedules to dispatch
  def notify_and_dispatch(trigger, time)
    catch(:halt) { notify_at(trigger, time) }
    settle(trigger)
  end

  # A process that went down coming back up
  def starting
    Bluepill::Process::Transition.new(:down, :starting)
  end

  # What the trigger has logged, and its timeline
  def history(trigger)
    [calls.dup, trigger.timeline.dup]
  end

  def notify_at(trigger, time, transition = starting)
    allow(Bluepill::Clock).to receive(:now).and_return(time)
    trigger.notify(transition)
  end

  describe "#initialize" do
    it "uses default parameters" do
      expect(flapping).to have_attributes(times: 5, within: 1, retry_in: 5, logger: logger, timeline: [])
    end

    it "accepts parameters" do
      expect(flapping(times: 2, within: 10, retry_in: 30)).to have_attributes(times: 2, within: 10, retry_in: 30)
    end

    it "can be created without options" do
      expect(described_class.new(process)).to have_attributes(times: 5, within: 1, retry_in: 5, logger: nil)
    end

    it "ignores options it does not know" do
      trigger = flapping(every: 10)
      expect(trigger.instance_variable_defined?(:@every)).to be false
    end

    it "keeps as many incidents as times" do
      trigger = flapping(times: 2)
      trigger.timeline << 1 << 2 << 3
      expect(trigger.timeline).to eq([2, 3])
    end
  end

  describe "#notify" do
    it "ignores transitions to other states" do
      trigger = flapping(times: 1)
      notify_at(trigger, 0, Bluepill::Process::Transition.new(:starting, :up))
      expect(trigger.timeline).to eq([])
    end

    it "records restarts" do
      trigger = flapping
      notify_at(trigger, 0, Bluepill::Process::Transition.new(:up, :restarting))
      expect(trigger.timeline).to eq([0])
    end

    it "does not detect flapping before enough incidents" do
      trigger = flapping(times: 2)
      notify_at(trigger, 0)
      expect(calls).to eq([])
    end

    it "does not detect flapping when the incidents are spread out" do
      trigger = flapping(times: 2, within: 10)
      notify_at(trigger, 100)
      notify_at(trigger, 111)
      expect(history(trigger)).to eq([[], [100, 111]])
    end

    context "when the process flaps" do
      let(:trigger) { flapping(times: 2, within: 10, retry_in: 30) }

      before do
        record_dispatches
        notify_at(trigger, 100)
      end

      after { settle(trigger) }

      it "halts the transition" do
        expect { notify_at(trigger, 110) }.to throw_symbol(:halt)
      end

      it "logs it, and clears the timeline" do
        notify_and_dispatch(trigger, 110)
        expect(history(trigger)).to eq([[[:info, "Flapping detected: retrying in 30 seconds"]], []])
      end

      it "retries after retry_in, and unmonitors the process at once" do
        notify_and_dispatch(trigger, 110)
        expect(dispatched).to contain_exactly([:start, "Flapping", 30.0], [:unmonitor, "Flapping", 0.0])
      end
    end

    it "accepts a Float times" do
      record_dispatches
      trigger = flapping(times: 2.0, within: 10)
      notify_at(trigger, 100)
      notify_and_dispatch(trigger, 105)
      expect(dispatched.collect(&:first)).to contain_exactly(:start, :unmonitor)
    end

    it "does not retry when retry_in is zero" do
      record_dispatches
      notify_and_dispatch(flapping(times: 1, retry_in: 0), 0)
      expect([calls, dispatched]).to eq([[[:info, "Flapping detected: retrying in 0 seconds"]], [[:unmonitor, "Flapping", 0.0]]])
    end
  end

  describe "#reset!" do
    it "clears the timeline and cancels scheduled events" do
      trigger = flapping
      notify_at(trigger, 0)
      trigger.reset!
      expect(history(trigger)).to eq([[[:info, "Canceling all scheduled events"]], []])
    end
  end
end
