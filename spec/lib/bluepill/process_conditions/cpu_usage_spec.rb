describe Bluepill::ProcessConditions::CpuUsage do
  subject { Bluepill::ProcessConditions::CpuUsage.new(below: 50) }

  it 'can be created without options' do
    expect(Bluepill::ProcessConditions::CpuUsage.new).to be_a(Bluepill::ProcessConditions::CpuUsage)
  end

  it 'returns the cpu usage of the process as a float' do
    expect(Bluepill::System).to receive(:cpu_usage).with(123, true).and_return(12)
    expect(subject.run(123, true)).to eq(12.0)
  end

  it 'passes when the usage is below the limit' do
    expect(subject.check(49.9)).to be true
  end

  it 'fails when the usage is not below the limit' do
    expect(subject.check(50.0)).to be false
  end
end
