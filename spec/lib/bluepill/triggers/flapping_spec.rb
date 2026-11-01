describe Bluepill::Triggers::Flapping do
  let(:process) { instance_double(Bluepill::Process) }
  let(:logger) { instance_double(Bluepill::Logger, info: nil) }
  let(:starting) { double('transition', to_name: :starting) }

  def flapping(options = {})
    trigger = Bluepill::Triggers::Flapping.new(process, {logger: logger}.merge(options))
    allow(trigger).to receive(:schedule_event)
    trigger
  end

  def notify_at(trigger, time, transition = starting)
    allow(Time).to receive(:now).and_return(Time.at(time))
    trigger.notify(transition)
  end

  describe '#initialize' do
    it 'uses default parameters' do
      trigger = flapping
      expect([trigger.times, trigger.within, trigger.retry_in]).to eq([5, 1, 5])
      expect(trigger.logger).to eq(logger)
      expect(trigger.timeline).to eq([])
    end

    it 'accepts parameters' do
      trigger = flapping(times: 2, within: 10, retry_in: 30)
      expect([trigger.times, trigger.within, trigger.retry_in]).to eq([2, 10, 30])
    end
  end

  describe '#notify' do
    it 'ignores transitions to other states' do
      trigger = flapping(times: 1)
      notify_at(trigger, 0, double('transition', to_name: :up))
      expect(trigger.timeline).to eq([])
    end

    it 'records restarts' do
      trigger = flapping
      notify_at(trigger, 0, double('transition', to_name: :restarting))
      expect(trigger.timeline).to eq([0])
    end

    it 'does not detect flapping before enough incidents' do
      trigger = flapping(times: 2)
      notify_at(trigger, 0)
      expect(trigger).not_to have_received(:schedule_event)
    end

    it 'does not detect flapping when the incidents are spread out' do
      trigger = flapping(times: 2, within: 10)
      notify_at(trigger, 0)
      notify_at(trigger, 11)
      expect(trigger).not_to have_received(:schedule_event)
      expect(trigger.timeline).to eq([0, 11])
    end

    it 'detects flapping, schedules a retry and halts the transition' do
      trigger = flapping(times: 2, within: 10, retry_in: 30)
      notify_at(trigger, 0)
      expect { notify_at(trigger, 10) }.to throw_symbol(:halt)
      expect(logger).to have_received(:info).with('Flapping detected: retrying in 30 seconds')
      expect(trigger).to have_received(:schedule_event).with(:start, 30)
      expect(trigger).to have_received(:schedule_event).with(:unmonitor, 0)
      expect(trigger.timeline).to eq([])
    end

    it 'does not retry when retry_in is zero' do
      trigger = flapping(times: 1, retry_in: 0)
      expect { notify_at(trigger, 0) }.to throw_symbol(:halt)
      expect(trigger).not_to have_received(:schedule_event).with(:start, anything)
      expect(trigger).to have_received(:schedule_event).with(:unmonitor, 0)
    end
  end

  describe '#reset!' do
    it 'clears the timeline and cancels scheduled events' do
      trigger = flapping
      notify_at(trigger, 0)
      trigger.reset!
      expect(trigger.timeline).to eq([])
      expect(logger).to have_received(:info).with('Canceling all scheduled events')
    end
  end
end
