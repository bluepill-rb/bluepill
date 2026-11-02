# frozen_string_literal: true

describe Bluepill::ProcessConditions::ProcessCondition do
  subject(:condition) { described_class.new }

  it "keeps its logger" do
    logger = instance_double(Bluepill::Logger)
    expect(described_class.new(logger:).logger).to equal(logger)
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

  describe ".inherited" do
    around do |example|
      entries = Bluepill::CheckRegistry.instance_variable_get(:@entries).dup
      example.run
      Bluepill::CheckRegistry.instance_variable_set(:@entries, entries)
    end

    it "adds a subclass to the registry, wherever it's defined, by its underscored name" do
      klass = stub_const("SpecApp::DiskFree", Class.new(described_class) do
        define_method(:run) { |_pid, _children| 1 }
        define_method(:check?) { |_value| true }
      end)
      expect(Bluepill::CheckRegistry.fetch(:disk_free)).to equal(klass)
    end

    it "requires a subclass to define run and check?" do
      stub_const("SpecApp::DiskFree", Class.new(described_class))
      message = "SpecApp::DiskFree, the class of check 'disk_free', must define run and check?"
      expect { Bluepill::CheckRegistry.fetch(:disk_free) }.to raise_error(Bluepill::ConfigError, message)
    end

    it "calls the inherited hook of its superclass" do
      allow(Object).to receive(:inherited).and_call_original
      klass = Class.new(described_class)
      expect(Object).to have_received(:inherited).with(klass)
    end
  end

  it "formats values as is" do
    expect(condition.format_value(42)).to eq(42)
  end
end
