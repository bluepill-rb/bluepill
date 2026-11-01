describe Bluepill::ProcessConditions::ProcessCondition do
  subject { Bluepill::ProcessConditions::ProcessCondition.new(below: 5) }

  it 'stores its options' do
    expect(subject.instance_variable_get(:@options)).to eq(below: 5)
  end

  it 'takes its logger out of its options' do
    logger = double('logger')
    condition = Bluepill::ProcessConditions::ProcessCondition.new(below: 5, logger: logger)
    expect(condition.logger).to equal(logger)
    expect(condition.instance_variable_get(:@options)).to eq(below: 5)
  end

  it 'has no logger without one' do
    expect(subject.logger).to be_nil
  end

  it 'can be created without options' do
    expect(Bluepill::ProcessConditions::ProcessCondition.new.instance_variable_get(:@options)).to eq({})
  end

  it 'requires subclasses to implement #run' do
    expect { subject.run(123, false) }.to raise_error('Implement in subclass!')
  end

  it 'requires subclasses to implement #check' do
    expect { subject.check(1) }.to raise_error('Implement in subclass!')
  end

  it 'formats values as is' do
    expect(subject.format_value(42)).to eq(42)
  end
end
