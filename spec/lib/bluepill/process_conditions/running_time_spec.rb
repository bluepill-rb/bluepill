# frozen_string_literal: true

describe Bluepill::ProcessConditions::RunningTime do
  subject(:condition) { described_class.new(below: 60) }

  it "needs its below option" do
    expect { described_class.new }.to raise_error(ArgumentError, /missing keyword: :below/)
  end

  it "keeps the options it doesn't take" do
    extra = described_class.new(below: 60, note: "x")
    expect(extra.instance_variable_get(:@options)).to eq(note: "x")
  end

  it "returns the running time of the process" do
    allow(Bluepill::System).to receive(:running_time).with(123).and_return(30)
    expect(condition.run(123, false)).to eq(30)
  end

  it "returns 0 for a process that ps does not list" do
    allow(Bluepill::System).to receive(:running_time).with(123).and_return(nil)
    expect(condition.run(123, false)).to eq(0)
  end

  it "passes when the running time is below the limit" do
    expect(condition.check?(59)).to be true
  end

  it "fails when the running time is not below the limit" do
    expect(condition.check?(60)).to be false
  end
end
