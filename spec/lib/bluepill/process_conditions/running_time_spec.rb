describe Bluepill::ProcessConditions::RunningTime do
  subject { Bluepill::ProcessConditions::RunningTime.new(below: 60) }

  it 'can be created without options' do
    expect(Bluepill::ProcessConditions::RunningTime.new).to be_a(Bluepill::ProcessConditions::RunningTime)
  end

  it 'returns the running time of the process' do
    expect(Bluepill::System).to receive(:running_time).with(123).and_return(30)
    expect(subject.run(123, false)).to eq(30)
  end

  it 'passes when the running time is below the limit' do
    expect(subject.check(59)).to be true
  end

  it 'fails when the running time is not below the limit' do
    expect(subject.check(60)).to be false
  end
end
