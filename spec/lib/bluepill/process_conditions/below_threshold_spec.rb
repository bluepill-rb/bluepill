# frozen_string_literal: true

describe Bluepill::ProcessConditions::BelowThreshold do
  subject(:condition) { described_class.new(below: 50) }

  it "can be created without options" do
    expect(described_class.new).to be_a(described_class)
  end

  it "stores its options" do
    expect(condition.instance_variable_get(:@options)).to eq(below: 50)
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
