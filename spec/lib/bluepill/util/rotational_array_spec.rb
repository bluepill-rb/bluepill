describe Bluepill::Util::RotationalArray do
  subject { described_class.new(3) }

  it 'starts empty' do
    expect(subject).to be_empty
  end

  it 'keeps values up to its capacity' do
    subject.push(1).push(2)
    expect(subject).to eq([1, 2])
  end

  it 'drops the oldest values beyond its capacity' do
    subject.push(1).push(2).push(3).push(4)
    expect(subject).to eq([2, 3, 4])
  end

  it 'drops the oldest values beyond its capacity with <<' do
    subject << 1 << 2 << 3 << 4
    expect(subject).to eq([2, 3, 4])
  end

  it 'starts empty again when re-initialized' do
    subject.push(1).push(2)
    subject.send(:initialize, 1)
    expect(subject).to eq([])
    subject.push(1).push(2)
    expect(subject).to eq([2])
  end

  it 'returns itself from push' do
    expect(subject.push(1)).to equal(subject)
  end
end
