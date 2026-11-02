# frozen_string_literal: true

describe Bluepill::ProcessConditions::AlwaysTrue do
  subject(:condition) { described_class.new }

  it "rejects an option it doesn't take" do
    expect { described_class.new(below: 5) }.to raise_error(ArgumentError, /unknown keyword: :below/)
  end

  it "always returns 1" do
    expect(condition.run(123, false)).to eq(1)
  end

  it "always passes" do
    expect(condition.check?(100)).to be true
  end
end
