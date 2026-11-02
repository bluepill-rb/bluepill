# frozen_string_literal: true

describe Bluepill::ProcessConditions::ProcessCondition do
  subject(:condition) { described_class.new(below: 5) }

  it "stores its options" do
    expect(condition.instance_variable_get(:@options)).to eq(below: 5)
  end

  context "with a logger" do
    subject(:condition) { described_class.new(below: 5, logger: logger) }

    let(:logger) { instance_double(Bluepill::Logger) }

    it "takes its logger out of its options" do
      expect(condition.logger).to equal(logger)
    end

    it "leaves the logger out of the options it stores" do
      expect(condition.instance_variable_get(:@options)).to eq(below: 5)
    end
  end

  it "has no logger without one" do
    expect(condition.logger).to be_nil
  end

  it "can be created without options" do
    expect(described_class.new.instance_variable_get(:@options)).to eq({})
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
