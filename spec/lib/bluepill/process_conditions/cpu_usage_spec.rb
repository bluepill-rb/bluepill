# frozen_string_literal: true

describe Bluepill::ProcessConditions::CpuUsage do
  subject(:condition) { described_class.new(below: 50) }

  it "needs its below option" do
    expect { described_class.new }.to raise_error(ArgumentError, /missing keyword: :below/)
  end

  it "rejects an option it doesn't take" do
    expect { described_class.new(below: 50, note: "x") }.to raise_error(ArgumentError, /unknown keyword: :note/)
  end

  it "returns the cpu usage of the process as a float" do
    allow(Bluepill::System).to receive(:cpu_usage).with(123, true).and_return(12.5)
    expect(condition.run(123, true)).to be_a(Float).and eq(12.5)
  end

  it "returns 0.0 for a process that ps does not list" do
    allow(Bluepill::System).to receive(:cpu_usage).with(123, false).and_return(nil)
    expect(condition.run(123, false)).to be_a(Float).and eq(0.0)
  end

  it "passes when the usage is below the limit" do
    expect(condition.check?(49.9)).to be true
  end

  it "fails when the usage is not below the limit" do
    expect(condition.check?(50.0)).to be false
  end
end
