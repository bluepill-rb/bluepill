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

  it "requires subclasses to implement #check, if they call it" do
    expect { condition.check(1) }.to raise_error("Implement in subclass!")
  end

  context "with a check written for bluepill 0.1" do
    let(:old_style) do
      Class.new(described_class) do
        def check(value) # rubocop:disable Naming/PredicateMethod -- the name bluepill 0.1 used
          value > 1
        end
      end.new
    end

    it "passes check? on to check, as bluepill 0.1 named it" do
      expect([old_style.check?(2), old_style.check?(1)]).to eq([true, false])
    end
  end

  it "formats values as is" do
    expect(condition.format_value(42)).to eq(42)
  end

  context "when its logger is set" do
    let(:logger) { instance_double(Bluepill::Logger) }

    it "sets the logger" do
      allow($stderr).to receive(:puts)
      condition.logger = logger
      expect(condition.logger).to equal(logger)
    end

    it "warns, with where it was called from, when code outside bluepill calls it" do
      line = __LINE__ + 1
      expect { condition.logger = logger }.to output(
        /which #{Regexp.escape(__FILE__)}:#{line}:in .* on Bluepill::ProcessConditions::ProcessCondition\./
      ).to_stderr
    end

    it "says nothing when bluepill's watch sets it" do
      watch = Bluepill::ConditionWatch.new(:always_true, every: 10)
      expect { watch.logger = logger }.not_to output.to_stderr
    end
  end
end
