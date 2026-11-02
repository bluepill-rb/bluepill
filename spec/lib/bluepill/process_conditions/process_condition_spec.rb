# frozen_string_literal: true

describe Bluepill::ProcessConditions::ProcessCondition do
  subject(:condition) { described_class.new }

  it "keeps its logger" do
    logger = instance_double(Bluepill::Logger)
    expect(described_class.new(logger: logger).logger).to equal(logger)
  end

  it "has no logger without one" do
    expect(condition.logger).to be_nil
  end

  it "rejects an option it doesn't take" do
    expect { described_class.new(below: 5) }.to raise_error(ArgumentError, /unknown keyword: :below/)
  end

  it "requires subclasses to implement #run" do
    expect { condition.run(123, false) }.to raise_error("Implement in subclass!")
  end

  it "requires subclasses to implement #check?" do
    expect { condition.check?(1) }.to raise_error("Implement in subclass!")
  end

  it "formats values as is" do
    expect(condition.format_value(42)).to eq(42)
  end
end
