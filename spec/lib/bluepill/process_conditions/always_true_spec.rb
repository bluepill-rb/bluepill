describe Bluepill::ProcessConditions::AlwaysTrue do
  subject(:condition) { described_class.new(below: 5) }

  it 'can be created without options' do
    expect(described_class.new).to be_a(described_class)
  end

  it 'stores its options' do
    expect(condition.instance_variable_get(:@options)).to eq(below: 5)
  end

  it 'always returns 1' do
    expect(condition.run(123, false)).to eq(1)
  end

  it 'always passes' do
    expect(condition.check?(100)).to be true
  end
end
