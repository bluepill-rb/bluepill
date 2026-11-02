describe Bluepill::ProcessConditions::RunningTime do
  subject(:condition) { described_class.new(below: 60) }

  it 'can be created without options' do
    expect(described_class.new).to be_a(described_class)
  end

  it 'stores its options' do
    expect(condition.instance_variable_get(:@options)).to eq(below: 60)
  end

  it 'returns the running time of the process' do
    allow(Bluepill::System).to receive(:running_time).with(123).and_return(30)
    expect(condition.run(123, false)).to eq(30)
  end

  it 'returns 0 for a process that ps does not list' do
    allow(Bluepill::System).to receive(:running_time).with(123).and_return(nil)
    expect(condition.run(123, false)).to eq(0)
  end

  it 'passes when the running time is below the limit' do
    expect(condition.check?(59)).to be true
  end

  it 'fails when the running time is not below the limit' do
    expect(condition.check?(60)).to be false
  end
end
