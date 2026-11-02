# frozen_string_literal: true

describe Bluepill::Process::StopSignals do
  subject(:signals) { described_class.new([:quit, 30, :term, 5, :kill]) }

  describe ".from" do
    it "parses an Array" do
      expect(described_class.from([:quit, 30, :kill]).to_a).to eq([:quit, 30, :kill])
    end

    it "returns stop signals as they are" do
      expect(described_class.from(signals)).to equal(signals)
    end

    it "fails on an Array that doesn't alternate signals and delays" do
      expect { described_class.from([:quit, 30]) }.to raise_error(Bluepill::ConfigError, /odd number/)
    end
  end

  describe ".new" do
    it "is frozen" do
      expect(signals).to be_frozen
    end

    it "keeps its own copy of the signals and delays" do
      array = [:quit, 30, :kill]
      stop_signals = described_class.new(array)
      array.replace([:term])
      expect(stop_signals.to_a).to eq([:quit, 30, :kill])
    end

    it "rejects a signal that isn't a Symbol, saying where" do
      expect { described_class.new([:quit, 5, "term"]) }.to raise_error(
        Bluepill::ConfigError, "Config Error: Invalid stop_signals!  Expected a symbol (signal) at position 2 instead of 'term'."
      )
    end

    it "rejects a delay that isn't an Integer, saying where" do
      expect { described_class.new([:quit, "five", :term]) }.to raise_error(
        Bluepill::ConfigError, "Config Error: Invalid stop_signals!  Expected a number (delay) at position 1 instead of 'five'."
      )
    end

    # An Integer that isn't an instance of Integer. Every Integer is one
    # since Ruby 2.4, so this keeps is_a? from passing as instance_of?.
    it "accepts any kind of Integer as a delay" do
      delay = instance_double(Integer, is_a?: true)
      expect(described_class.new([:quit, delay, :term]).to_a).to eq([:quit, delay, :term])
    end

    it "rejects the first mistake" do
      expect { described_class.new(["quit", "five", :term]) }.to raise_error(Bluepill::ConfigError, /at position 0/)
    end

    it "rejects a mistake before the 'odd number' one" do
      expect { described_class.new([:quit, :term]) }.to raise_error(Bluepill::ConfigError, /at position 1 instead of 'term'/)
    end

    it "rejects an even number of elements" do
      expect { described_class.new([:quit, 5]) }.to raise_error(
        Bluepill::ConfigError, "Config Error: Invalid stop_signals!  Expected an odd number of elements."
      )
    end

    it "rejects no signals" do
      expect { described_class.new([]) }.to raise_error(Bluepill::ConfigError, /odd number/)
    end
  end

  describe "#first_signal" do
    it "is the first element" do
      expect(signals.first_signal).to eq(:quit)
    end
  end

  describe "#later_signals" do
    it "pairs each later signal with the delay before it" do
      expect(signals.later_signals).to eq([[30, :term], [5, :kill]])
    end

    it "is frozen" do
      expect(signals.later_signals).to be_frozen
    end

    it "is empty for a single signal" do
      expect(described_class.new([:term]).later_signals).to be_empty
    end
  end

  describe "#total_delay" do
    it "adds up the delays" do
      expect(signals.total_delay).to eq(35)
    end

    it "is 0 for a single signal" do
      expect(described_class.new([:term]).total_delay).to eq(0)
    end
  end

  describe "#to_a" do
    it "returns the signals and delays" do
      expect(signals.to_a).to eq([:quit, 30, :term, 5, :kill])
    end
  end
end
