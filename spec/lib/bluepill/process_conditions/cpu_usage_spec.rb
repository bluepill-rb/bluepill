describe Bluepill::ProcessConditions::CpuUsage do
  subject { described_class.new(below: 50) }

  it 'can be created without options' do
    expect(described_class.new).to be_a(described_class)
  end

  it 'stores its options' do
    expect(subject.instance_variable_get(:@options)).to eq(below: 50)
  end

  it 'returns the cpu usage of the process as a float' do
    expect(Bluepill::System).to receive(:cpu_usage).with(123, true).and_return(12.5)
    expect(subject.run(123, true)).to be(12.5)
  end

  it 'returns 0.0 for a process that ps does not list' do
    expect(Bluepill::System).to receive(:cpu_usage).with(123, false).and_return(nil)
    expect(subject.run(123, false)).to be(0.0)
  end

  it 'passes when the usage is below the limit' do
    expect(subject.check?(49.9)).to be true
  end

  it 'fails when the usage is not below the limit' do
    expect(subject.check?(50.0)).to be false
  end
end
