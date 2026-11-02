describe Bluepill::ProcessConditions::AlwaysTrue do
  subject { Bluepill::ProcessConditions::AlwaysTrue.new(below: 5) }

  it 'can be created without options' do
    expect(Bluepill::ProcessConditions::AlwaysTrue.new).to be_a(Bluepill::ProcessConditions::AlwaysTrue)
  end

  it 'stores its options' do
    expect(subject.instance_variable_get(:@options)).to eq(below: 5)
  end

  it 'always returns 1' do
    expect(subject.run(123, false)).to eq(1)
  end

  it 'always passes' do
    expect(subject.check?(100)).to be true
  end
end
