# frozen_string_literal: true

describe Bluepill::Process::Triggers do
  subject(:triggers) { described_class.new(logger:) }

  let(:logger) { instance_double(Bluepill::Logger) }
  let(:process) { instance_double(Bluepill::Process) }
  let(:transition) { Bluepill::Process::Transition.new(:up, :down) }
  # What the triggers are told, in order
  let(:calls) { [] }

  # A trigger that records what it's told as [method, name, *args]
  def trigger_double(name)
    trigger = instance_double(Bluepill::Trigger, name)
    %i[notify reset!].each do |method|
      allow(trigger).to receive(method) { |*args| calls << [method, name, *args] }
    end
    trigger
  end

  describe "#add" do
    it "adds a trigger of the class, for the process, with its options and the logger, and returns the triggers" do
      expect([triggers.add(Bluepill::Triggers::Flapping, process, times: 2), triggers.to_a]).to match(
        [be(triggers), [be_a(Bluepill::Triggers::Flapping).and(have_attributes(process:, logger:, times: 2))]]
      )
    end
  end

  describe "#<<" do
    it "adds the trigger, after the others, and returns the triggers" do
      first = trigger_double("first")
      second = trigger_double("second")
      expect([triggers << first << second, triggers.to_a]).to eq([triggers, [first, second]])
    end
  end

  describe "#each" do
    it "yields each trigger and returns them" do
      trigger = trigger_double("trigger")
      triggers << trigger
      yielded = []
      expect([triggers.each { |t| yielded << t }, yielded]).to eq([[trigger], [trigger]])
    end
  end

  describe "#initialize" do
    it "has no triggers, and the logger it gives the triggers added" do
      expect([triggers.to_a, triggers.logger]).to match([[], be(logger)])
    end
  end

  describe "#notify" do
    before { %w[first second].each { |name| triggers << trigger_double(name) } }

    it "tells each trigger of the transition, in order" do
      triggers.notify(transition)
      expect(calls).to eq([[:notify, "first", transition], [:notify, "second", transition]])
    end

    it "returns the triggers" do
      expect(triggers.notify(transition)).to eq(triggers.to_a)
    end

    it "goes through its triggers without each, which would cost a call on every tick" do
      others = described_class.new(logger:) << trigger_double("other")
      allow(others).to receive(:each).and_raise("each called")
      expect(others.notify(transition).size).to eq(1)
    end

    context "when a trigger raises" do
      before { allow(triggers.first).to receive(:notify).and_raise("boom") }

      it "lets the error through" do
        expect { triggers.notify(transition) }.to raise_error("boom")
      end

      it "tells no trigger after it" do
        triggers.notify(transition)
      rescue RuntimeError
        expect(calls).to eq([])
      end
    end
  end

  describe "#reset!" do
    it "resets each trigger, in order, and returns them" do
      %w[first second].each { |name| triggers << trigger_double(name) }
      expect([triggers.reset!, calls]).to eq([triggers.to_a, [[:reset!, "first"], [:reset!, "second"]]])
    end
  end
end
