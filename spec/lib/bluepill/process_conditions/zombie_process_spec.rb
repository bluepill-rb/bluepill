describe Bluepill::ProcessConditions::ZombieProcess do
  subject { Bluepill::ProcessConditions::ZombieProcess.new }

  it 'returns the command of the process' do
    expect(Bluepill::System).to receive(:command).with(123).and_return('ruby server.rb')
    expect(subject.run(123, false)).to eq('ruby server.rb')
  end

  it 'passes when the process is not defunct' do
    expect(subject.check('ruby server.rb')).to be true
  end

  it 'fails when the process is defunct' do
    expect(subject.check('[ruby] <defunct>')).to be false
  end
end
