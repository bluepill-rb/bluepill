describe Bluepill::Trigger do
  subject(:trigger) { described_class.new(process, logger: logger) }

  let(:process) { instance_double(Bluepill::Process, dispatch!: nil) }
  let(:logger) { instance_double(Bluepill::Logger, info: nil, err: nil) }

  describe '.[]' do
    it 'looks up registered triggers by name' do
      expect(described_class[:flapping]).to eq(Bluepill::Triggers::Flapping)
    end

    it 'returns nil for unknown triggers' do
      expect(described_class[:unknown]).to be_nil
    end
  end

  describe '.inherited' do
    let(:klass) { Class.new }

    before do
      allow(klass).to receive(:name).and_return('Bluepill::Triggers::SpecExample')
      allow(Object).to receive(:inherited).and_call_original
    end

    after do
      described_class.instance_variable_get(:@implementations).delete(:spec_example)
    end

    it 'registers subclasses by their underscored name' do
      described_class.send(:inherited, klass)
      expect(described_class[:spec_example]).to equal(klass)
    end

    it 'calls the inherited hook of its superclass' do
      described_class.send(:inherited, klass)
      expect(Object).to have_received(:inherited).with(klass)
    end
  end

  describe '#initialize' do
    it 'sets up the trigger' do
      expect(trigger.process).to eq(process)
      expect(trigger.logger).to eq(logger)
      expect(trigger.mutex).to be_a(Mutex)
      expect(trigger.scheduled_events).to eq([])
    end

    it 'can be created without options' do
      expect(described_class.new(process).logger).to be_nil
    end
  end

  describe '#notify' do
    it 'must be implemented by subclasses' do
      expect { trigger.notify(nil) }.to raise_error('Implement in subclass')
    end
  end

  describe '#dispatch!' do
    it 'dispatches the event to the process with the trigger name as reason' do
      trigger.dispatch!(:start)
      expect(process).to have_received(:dispatch!).with(:start, 'Trigger')
    end
  end

  describe '#schedule_event' do
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

    it 'sleeps before it dispatches the event' do
      events = []
      allow(process).to receive(:dispatch!) { events << :dispatched }
      thread = trigger.schedule_event(:start, 60)
      Thread.pass while thread.status == 'run'
      events << thread.status
      finish(thread)
      expect(events).to eq(['sleep', :dispatched])
    end

    it 'dispatches the event once it wakes' do
      finish(trigger.schedule_event(:start, 60))
      expect(process).to have_received(:dispatch!).with(:start, 'Trigger')
    end

    it 'sleeps for a duration in seconds' do
      started = Time.now
      trigger.schedule_event(:start, 0.05.seconds).join
      expect(Time.now - started).to be >= 0.05
    end

    it 'records the scheduled events in order until each one is dispatched' do
      first = trigger.schedule_event(:start, 60)
      second = trigger.schedule_event(:stop, 60)
      expect(trigger.scheduled_events).to eq([[:start, first], [:stop, second]])
      finish(first)
      expect(trigger.scheduled_events).to eq([[:stop, second]])
      finish(second)
      expect(trigger.scheduled_events).to eq([])
    end

    it 'removes a dispatched event only after it was recorded' do
      dispatched = Queue.new
      worker = nil
      allow(process).to receive(:dispatch!) do
        worker = Thread.current
        dispatched.push(nil)
      end
      allow(trigger.scheduled_events).to receive(:push).and_wrap_original do |push, *args|
        # Wait until the event thread has dispatched and is waiting for the lock or done
        dispatched.pop
        Thread.pass while worker.status == 'run'
        push.call(*args)
      end
      trigger.schedule_event(:start, 0).join
      expect(trigger.scheduled_events).to eq([])
    end

    it 'logs errors without a backtrace' do
      error = RuntimeError.new('boom')
      allow(error).to receive(:backtrace).and_return(nil)
      allow(process).to receive(:dispatch!).and_raise(error)
      trigger.schedule_event(:start, 0).join
      expect(logger).to have_received(:err).with(error)
      expect(logger).to have_received(:err).with('')
    end

    it 'logs errors raised while dispatching' do
      error = RuntimeError.new('boom')
      error.set_backtrace(['line 1', 'line 2'])
      allow(process).to receive(:dispatch!).and_raise(error)
      trigger.schedule_event(:start, 0).join
      expect(logger).to have_received(:err).with(error)
      expect(logger).to have_received(:err).with("line 1\nline 2")
    end
  end

  describe '#reset!' do
    it 'cancels all scheduled events' do
      thread = instance_double(Thread)
      locked = nil
      allow(thread).to receive(:kill) { locked = trigger.mutex.locked? }
      trigger.scheduled_events.push([:start, thread])
      trigger.reset!
      expect(logger).to have_received(:info).with('Canceling all scheduled events')
      expect(thread).to have_received(:kill)
      expect(locked).to be true
      expect(trigger.scheduled_events).to eq([])
    end
  end
end
