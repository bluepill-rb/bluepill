describe Bluepill::Triggers::Flapping do
  # What the trigger logs and schedules, in order
  let(:calls) { [] }
  let(:process) { instance_double(Bluepill::Process) }
  let(:logger) { record(instance_double(Bluepill::Logger), :info) }
  let(:starting) { Bluepill::Process::Transition.new(:down, :starting) }

  # Record each method's calls in calls, as [method, *args]
  def record(double, *methods)
    methods.each do |method|
      allow(double).to receive(method) { |*args| calls << [method, *args] }
    end
    double
  end

  def flapping(options = {})
    record(Bluepill::Triggers::Flapping.new(process, {logger: logger}.merge(options)), :schedule_event)
  end

  # What the trigger has logged and scheduled, and its timeline
  def history(trigger)
    [calls.dup, trigger.timeline.dup]
  end

  def notify_at(trigger, time, transition = starting)
    allow(Time).to receive(:now).and_return(Time.at(time))
    trigger.notify(transition)
  end

  describe '#initialize' do
    it 'uses default parameters' do
      expect(flapping).to have_attributes(times: 5, within: 1, retry_in: 5, logger: logger, timeline: [])
    end

    it 'accepts parameters' do
      expect(flapping(times: 2, within: 10, retry_in: 30)).to have_attributes(times: 2, within: 10, retry_in: 30)
    end

    it 'can be created without options' do
      expect(described_class.new(process)).to have_attributes(times: 5, within: 1, retry_in: 5, logger: nil)
    end

    it 'ignores options it does not know' do
      trigger = flapping(every: 10)
      expect(trigger.instance_variable_defined?(:@every)).to be false
    end

    it 'keeps as many incidents as times' do
      trigger = flapping(times: 2)
      trigger.timeline << 1 << 2 << 3
      expect(trigger.timeline).to eq([2, 3])
    end
  end

  describe '#notify' do
    it 'ignores transitions to other states' do
      trigger = flapping(times: 1)
      notify_at(trigger, 0, Bluepill::Process::Transition.new(:starting, :up))
      expect(trigger.timeline).to eq([])
    end

    it 'records restarts' do
      trigger = flapping
      notify_at(trigger, 0, Bluepill::Process::Transition.new(:up, :restarting))
      expect(trigger.timeline).to eq([0])
    end

    it 'does not detect flapping before enough incidents' do
      trigger = flapping(times: 2)
      notify_at(trigger, 0)
      expect(calls).to eq([])
    end

    it 'does not detect flapping when the incidents are spread out' do
      trigger = flapping(times: 2, within: 10)
      notify_at(trigger, 100)
      notify_at(trigger, 111)
      expect(history(trigger)).to eq([[], [100, 111]])
    end

    it 'detects flapping, schedules a retry and halts the transition' do
      trigger = flapping(times: 2, within: 10, retry_in: 30)
      notify_at(trigger, 100)
      expect { notify_at(trigger, 110) }.to throw_symbol(:halt).and change { history(trigger) }.to(
        [[[:info, 'Flapping detected: retrying in 30 seconds'], [:schedule_event, :start, 30], [:schedule_event, :unmonitor, 0]], []]
      )
    end

    it 'accepts a Float times' do
      trigger = flapping(times: 2.0, within: 10)
      notify_at(trigger, 100)
      expect { notify_at(trigger, 105) }.to throw_symbol(:halt)
    end

    it 'does not retry when retry_in is zero' do
      trigger = flapping(times: 1, retry_in: 0)
      expect { notify_at(trigger, 0) }.to throw_symbol(:halt).and change(calls, :dup).to(
        [[:info, 'Flapping detected: retrying in 0 seconds'], [:schedule_event, :unmonitor, 0]]
      )
    end
  end

  describe '#reset!' do
    it 'clears the timeline and cancels scheduled events' do
      trigger = flapping
      notify_at(trigger, 0)
      trigger.reset!
      expect(history(trigger)).to eq([[[:info, 'Canceling all scheduled events']], []])
    end
  end
end
