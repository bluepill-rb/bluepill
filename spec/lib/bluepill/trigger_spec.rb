describe Bluepill::Trigger do
  let(:process) { instance_double(Bluepill::Process, dispatch!: nil) }
  let(:logger) { instance_double(Bluepill::Logger, info: nil, err: nil) }

  subject { Bluepill::Trigger.new(process, logger: logger) }

  describe '.[]' do
    it 'looks up registered triggers by name' do
      expect(Bluepill::Trigger[:flapping]).to eq(Bluepill::Triggers::Flapping)
    end

    it 'returns nil for unknown triggers' do
      expect(Bluepill::Trigger[:unknown]).to be_nil
    end
  end

  describe '.inherited' do
    let(:klass) { Class.new }

    before do
      allow(klass).to receive(:name).and_return('Bluepill::Triggers::SpecExample')
      allow(Object).to receive(:inherited).and_call_original
    end

    after do
      Bluepill::Trigger.instance_variable_get(:@implementations).delete(:spec_example)
    end

    it 'registers subclasses by their underscored name' do
      Bluepill::Trigger.send(:inherited, klass)
      expect(Bluepill::Trigger[:spec_example]).to equal(klass)
    end

    it 'calls the inherited hook of its superclass' do
      Bluepill::Trigger.send(:inherited, klass)
      expect(Object).to have_received(:inherited).with(klass)
    end
  end

  describe '#initialize' do
    it 'sets up the trigger' do
      expect(subject.process).to eq(process)
      expect(subject.logger).to eq(logger)
      expect(subject.mutex).to be_a(Mutex)
      expect(subject.scheduled_events).to eq([])
    end

    it 'can be created without options' do
      expect(Bluepill::Trigger.new(process).logger).to be_nil
    end
  end

  describe '#notify' do
    it 'must be implemented by subclasses' do
      expect { subject.notify(nil) }.to raise_error('Implement in subclass')
    end
  end

  describe '#dispatch!' do
    it 'dispatches the event to the process with the trigger name as reason' do
      subject.dispatch!(:start)
      expect(process).to have_received(:dispatch!).with(:start, 'Trigger')
    end
  end

  describe '#schedule_event' do
    before do
      allow(subject).to receive(:sleep)
    end

    it 'dispatches the event after the delay' do
      thread = subject.schedule_event(:start, 5)
      thread.join
      expect(subject.scheduled_events).to eq([])
      expect(subject).to have_received(:sleep).with(5.0)
      expect(process).to have_received(:dispatch!).with(:start, 'Trigger')
    end

    it 'sleeps for a duration in seconds' do
      subject.schedule_event(:start, 1.5.seconds).join
      expect(subject).to have_received(:sleep) { |delay| expect(delay).to eql(1.5) }
    end

    it 'records the scheduled events in order until each one is dispatched' do
      gates = {1.0 => Queue.new, 2.0 => Queue.new}
      allow(subject).to receive(:sleep) { |delay| gates.fetch(delay).pop }
      first = subject.schedule_event(:start, 1)
      second = subject.schedule_event(:stop, 2)
      expect(subject.scheduled_events).to eq([[:start, first], [:stop, second]])
      gates.fetch(1.0).push(nil)
      first.join
      expect(subject.scheduled_events).to eq([[:stop, second]])
      gates.fetch(2.0).push(nil)
      second.join
      expect(subject.scheduled_events).to eq([])
    end

    it 'removes a dispatched event only after it was recorded' do
      dispatched = Queue.new
      worker = nil
      allow(process).to receive(:dispatch!) do
        worker = Thread.current
        dispatched.push(nil)
      end
      allow(subject.scheduled_events).to receive(:push).and_wrap_original do |push, *args|
        # Wait until the event thread has dispatched and is waiting for the lock or done
        dispatched.pop
        Thread.pass while worker.status == 'run'
        push.call(*args)
      end
      subject.schedule_event(:start, 0).join
      expect(subject.scheduled_events).to eq([])
    end

    it 'logs errors without a backtrace' do
      error = RuntimeError.new('boom')
      allow(error).to receive(:backtrace).and_return(nil)
      allow(process).to receive(:dispatch!).and_raise(error)
      subject.schedule_event(:start, 0).join
      expect(logger).to have_received(:err).with('Trigger failed to dispatch start: RuntimeError: boom').once
      expect(logger).to have_received(:err).once
    end

    it 'logs errors raised while dispatching, with their backtrace' do
      error = RuntimeError.new('boom')
      error.set_backtrace(['line 1', 'line 2'])
      allow(process).to receive(:dispatch!).and_raise(error)
      subject.schedule_event(:start, 0).join
      expect(logger).to have_received(:err).with('Trigger failed to dispatch start: RuntimeError: boom').ordered
      expect(logger).to have_received(:err).with('line 1').ordered
      expect(logger).to have_received(:err).with('line 2').ordered
    end
  end

  describe '#reset!' do
    it 'cancels all scheduled events' do
      thread = instance_double(Thread)
      locked = nil
      allow(thread).to receive(:kill) { locked = subject.mutex.locked? }
      subject.scheduled_events.push([:start, thread])
      subject.reset!
      expect(logger).to have_received(:info).with('Canceling all scheduled events')
      expect(thread).to have_received(:kill)
      expect(locked).to be true
      expect(subject.scheduled_events).to eq([])
    end
  end
end
