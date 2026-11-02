# frozen_string_literal: true

describe Bluepill::ProcessConditions::MemUsage do
  subject(:condition) { described_class.new(below: 100.megabytes) }

  it "needs its below option" do
    expect { described_class.new }.to raise_error(ArgumentError, /missing keywords?: :?below/)
  end

  it "rejects an option it doesn't take" do
    options = {below: 100.megabytes, note: "x"}
    expect { described_class.new(**options) }.to raise_error(ArgumentError, /unknown keyword: :note/)
  end

  it "returns the memory usage of the process in bytes as a float, from ps's kilobytes" do
    allow(Bluepill::System).to receive(:memory_usage).with(123, false).and_return(2048.5)
    expect(condition.run(123, false)).to be_a(Float).and eq(2048.5 * 1024)
  end

  it "returns 0.0 for a process that ps does not list" do
    allow(Bluepill::System).to receive(:memory_usage).with(123, false).and_return(nil)
    expect(condition.run(123, false)).to be_a(Float).and eq(0.0)
  end

  it "adds its children's usage when told to" do
    allow(Bluepill::System).to receive(:memory_usage).with(123, true).and_return(10)
    expect(condition.run(123, true)).to eq(10_240.0)
  end

  describe "#check?" do
    it "passes when the usage is below the limit" do
      expect(condition.check?(100.megabytes - 1)).to be true
    end

    it "fails when the usage is not below the limit" do
      expect(condition.check?(100.megabytes)).to be false
    end
  end

  describe "#format_value" do
    it "formats values of at least one megabyte in megabytes" do
      formatted = [1024.0, 2560.0, 10_751.0].collect { |kilobytes| condition.format_value(kilobytes * 1024) }
      expect(formatted).to eq(%w[1MB 3MB 10MB])
    end

    it "formats smaller values in kilobytes" do
      formatted = [1023.0, 1023.9, 0.5].collect { |kilobytes| condition.format_value(kilobytes * 1024) }
      expect(formatted).to eq(%w[1023KB 1023KB 0KB])
    end
  end
end
