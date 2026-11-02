# A trigger that a config could define, which reads what bluepill 0.2.0's
# transitions don't have
module Bluepill
  module Triggers
    class ReadsEvent < Trigger
      attr_reader :seen

      def notify(transition)
        @seen = [transition.to_name, transition.event]
      end
    end
  end
end

describe Bluepill::Trigger::Custom do
  let(:trigger) { instance_double(Bluepill::Trigger, notify: nil, reset!: nil, :logger= => nil) }
  let(:transition) { double('transition', from_name: :up, to_name: :down) }

  subject { described_class.new(trigger) }

  describe '#initialize' do
    it 'keeps the trigger' do
      expect(subject.trigger).to equal(trigger)
    end
  end

  describe '#notify' do
    it 'tells the trigger about the transition, wrapped' do
      wrapped = nil
      allow(trigger).to receive(:notify) { |t| wrapped = t }
      subject.notify(transition)
      expect(wrapped).to be_a(Bluepill::Trigger::Transition)
      expect(wrapped.from_name).to eq(:up)
      expect(wrapped.instance_variable_get(:@transition)).to equal(transition)
      expect(wrapped.instance_variable_get(:@trigger_class)).to equal(trigger.class)
    end
  end

  describe '#reset!' do
    it 'resets the trigger' do
      subject.reset!
      expect(trigger).to have_received(:reset!)
    end
  end

  describe '#logger=' do
    it 'sets the trigger\'s logger' do
      logger = instance_double(Bluepill::Logger)
      subject.logger = logger
      expect(trigger).to have_received(:logger=).with(logger)
    end
  end
end

describe Bluepill::Trigger::Transition do
  # Stands in for state_machine's transition, with a method it keeps private
  fake_transition = Struct.new(:from_name, :to_name, :event, :from, :to) do
    def loopback?
      from_name.equal?(to_name)
    end

    def perform(*args)
      [args, yield]
    end

  private

    def secret
      :hidden
    end
  end

  let(:transition) { fake_transition.new(:up, :down, :tick, 'up', 'down') }

  subject { described_class.new(transition, Bluepill::Triggers::ReadsEvent) }

  def warning(name)
    "DEPRECATION: bluepill 0.2.0 gives a trigger's notify a transition with only from_name, to_name and loopback?, " \
      "so Bluepill::Triggers::ReadsEvent's call of its #{name} fails there. Use from_name, to_name or loopback? instead.\n"
  end

  describe '#from_name' do
    it 'is the transition\'s, without a warning' do
      expect { expect(subject.from_name).to eq(:up) }.not_to output.to_stderr
    end
  end

  describe '#to_name' do
    it 'is the transition\'s, without a warning' do
      expect { expect(subject.to_name).to eq(:down) }.not_to output.to_stderr
    end
  end

  describe '#loopback?' do
    it 'is the transition\'s, without a warning' do
      loopback = described_class.new(fake_transition.new(:up, :up), Bluepill::Triggers::ReadsEvent)
      expect { expect(subject.loopback?).to be(false) }.not_to output.to_stderr
      expect(loopback.loopback?).to be(true)
    end
  end

  describe '#method_missing' do
    it 'calls what else the transition has, and warns once for each method and trigger' do
      expect do
        expect(subject.event).to eq(:tick)
        expect(subject.event).to eq(:tick)
        expect(subject.from).to eq('up')
      end.to output(warning(:event) + warning(:from)).to_stderr
    end

    it 'keys the warning by the trigger and the method' do
      expect(Bluepill::Deprecation).to receive(:warn).with([Bluepill::Triggers::ReadsEvent, :to], warning(:to).chomp.sub('DEPRECATION: ', ''))
      subject.to
    end

    it 'passes on the arguments and the block' do
      expect { expect(subject.perform(1, 2) { 3 }).to eq([[1, 2], 3]) }.to output(warning(:perform)).to_stderr
    end

    it 'raises NoMethodError, without a warning, for what the transition does not have' do
      expect { expect { subject.nonesuch }.to raise_error(NoMethodError) }.not_to output.to_stderr
    end

    it 'does not call the transition\'s private methods' do
      expect { subject.secret }.to raise_error(NoMethodError)
    end
  end

  describe '#respond_to_missing?' do
    it 'answers what the transition answers' do
      expect(subject).to respond_to(:event)
      expect(subject).not_to respond_to(:nonesuch)
      expect(subject.respond_to?(:event, true)).to be(true)
    end

    it 'passes on include_private' do
      expect(subject.respond_to?(:secret)).to be(false)
      expect(subject.respond_to?(:secret, true)).to be(true)
    end
  end

  it 'gives a custom trigger the event of a real transition, with a warning' do
    process = Bluepill::Process.new('web', {reads_event: {}}, logger: instance_double(Bluepill::Logger).as_null_object)
    allow(process).to receive(:start_process)
    expect { process.dispatch!(:start) }.to output(/ReadsEvent's call of its event/).to_stderr
    expect(process.triggers.first.trigger.seen).to eq([:starting, :start])
  end
end
