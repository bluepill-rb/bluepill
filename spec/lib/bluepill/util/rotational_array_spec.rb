describe Bluepill::Util::RotationalArray do
  subject { Bluepill::Util::RotationalArray.new(3) }

  it 'starts empty' do
    expect(subject).to be_empty
  end

  it 'keeps values up to its capacity' do
    subject.push(1).push(2)
    expect(subject).to eq([1, 2])
  end

  it 'drops the oldest values beyond its capacity' do
    subject << 1 << 2 << 3 << 4
    expect(subject).to eq([2, 3, 4])
  end

  it 'returns itself from push' do
    expect(subject.push(1)).to equal(subject)
  end
end
