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

  describe '#initialize' do
    it 'sets up the trigger' do
      expect(subject.process).to eq(process)
      expect(subject.logger).to eq(logger)
      expect(subject.mutex).to be_a(Mutex)
      expect(subject.scheduled_events).to eq([])
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

    it 'logs errors raised while dispatching' do
      error = RuntimeError.new('boom')
      error.set_backtrace(['line 1', 'line 2'])
      allow(process).to receive(:dispatch!).and_raise(error)
      subject.schedule_event(:start, 0).join
      expect(logger).to have_received(:err).with(error)
      expect(logger).to have_received(:err).with("line 1\nline 2")
    end
  end

  describe '#reset!' do
    it 'cancels all scheduled events' do
      thread = instance_double(Thread, kill: nil)
      subject.scheduled_events.push([:start, thread])
      subject.reset!
      expect(logger).to have_received(:info).with('Canceling all scheduled events')
      expect(thread).to have_received(:kill)
      expect(subject.scheduled_events).to eq([])
    end
  end
end
