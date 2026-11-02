# frozen_string_literal: true

describe Bluepill::ProcessConditions::MemUsage do
  subject(:condition) { described_class.new(below: 100.megabytes) }

  it "needs its below option" do
    expect { described_class.new }.to raise_error(ArgumentError, /missing keyword: :below/)
  end

  it "keeps the options it doesn't take" do
    extra = described_class.new(below: 100.megabytes, note: "x")
    expect(extra.instance_variable_get(:@options)).to eq(note: "x")
  end

  it "returns the memory usage of the process in kilobytes as a float" do
    allow(Bluepill::System).to receive(:memory_usage).with(123, false).and_return(2048.5)
    expect(condition.run(123, false)).to be_a(Float).and eq(2048.5)
  end

  it "returns 0.0 for a process that ps does not list" do
    allow(Bluepill::System).to receive(:memory_usage).with(123, false).and_return(nil)
    expect(condition.run(123, false)).to be_a(Float).and eq(0.0)
  end

  describe "#check?" do
    it "passes when the usage is below the limit" do
      expect(condition.check?(99 * 1024)).to be true
    end

    it "reads the usage in kilobytes of 1024 bytes" do
      expect(condition.check?(102_399)).to be true
    end

    it "fails when the usage is not below the limit" do
      expect(condition.check?(100 * 1024)).to be false
    end

    it "passes when the usage cannot be compared" do
      expect(condition.check?(nil)).to be true
    end
  end

  describe "#format_value" do
    it "formats values of at least one megabyte in megabytes" do
      expect([1024.0, 2560.0, 10_751.0].collect { |value| condition.format_value(value) }).to eq(%w[1MB 3MB 10MB])
    end

    it "formats smaller values in kilobytes" do
      expect([1023.0, 1023.9].collect { |value| condition.format_value(value) }).to eq(%w[1023KB 1023KB])
    end
  end
end
