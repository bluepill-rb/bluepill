describe Bluepill::ProcessConditions::ProcessCondition do
  subject { described_class.new(below: 5) }

  it 'stores its options' do
    expect(subject.instance_variable_get(:@options)).to eq(below: 5)
  end

  it 'takes its logger out of its options' do
    logger = double('logger')
    condition = described_class.new(below: 5, logger: logger)
    expect(condition.logger).to equal(logger)
    expect(condition.instance_variable_get(:@options)).to eq(below: 5)
  end

  it 'has no logger without one' do
    expect(subject.logger).to be_nil
  end

  it 'can be created without options' do
    expect(described_class.new.instance_variable_get(:@options)).to eq({})
  end

  it 'requires subclasses to implement #run' do
    expect { subject.run(123, false) }.to raise_error('Implement in subclass!')
  end

  it 'requires subclasses to implement #check? or #check' do
    expect { subject.check?(1) }.to raise_error('Implement in subclass!')
    expect { subject.check(1) }.to raise_error('Implement in subclass!')
  end

  it 'passes check? on to check, as bluepill 0.1 named it' do
    old_style = Class.new(described_class) do
      def check(value) # rubocop:disable Naming/PredicateMethod -- the name bluepill 0.1 used
        value > 1
      end
    end.new
    expect(old_style.check?(2)).to be true
    expect(old_style.check?(1)).to be false
  end

  it 'formats values as is' do
    expect(subject.format_value(42)).to eq(42)
  end
end
