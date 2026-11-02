# frozen_string_literal: true

describe Bluepill::Clock do
  describe ".now" do
    it "reads the monotonic clock in whole seconds" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :second).and_return(42)
      expect(described_class.now).to be(42)
    end

    it "returns an Integer that never goes back" do
      first = described_class.now
      expect(described_class.now).to be_an(Integer).and be >= first
    end
  end
end
