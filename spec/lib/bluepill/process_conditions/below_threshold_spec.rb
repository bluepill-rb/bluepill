# frozen_string_literal: true

describe Bluepill::ProcessConditions::BelowThreshold do
  subject(:condition) { described_class.new(below: 50) }

  it "needs its below option" do
    expect { described_class.new }.to raise_error(ArgumentError, /missing keyword: :below/)
  end

  it "keeps the options it doesn't take" do
    extra = described_class.new(below: 50, note: "x")
    expect(extra.instance_variable_get(:@options)).to eq(note: "x")
  end

  it "passes when the value is below the limit" do
    expect(condition.check?(49)).to be true
  end

  it "fails when the value is the limit" do
    expect(condition.check?(50)).to be false
  end

  it "fails when the value is above the limit" do
    expect(condition.check?(51)).to be false
  end

  it "is the base of the checks that compare a value with a limit" do
    conditions = Bluepill::ProcessConditions
    expect([conditions::CpuUsage, conditions::FileTime, conditions::MemUsage, conditions::RunningTime]).to all(be < described_class)
  end
end
