describe Bluepill::Util::RotationalArray do
  subject(:array) { described_class.new(3) }

  it 'starts empty' do
    expect(array).to be_empty
  end

  it 'keeps values up to its capacity' do
    array.push(1).push(2)
    expect(array).to eq([1, 2])
  end

  it 'drops the oldest values beyond its capacity' do
    array.push(1).push(2).push(3).push(4)
    expect(array).to eq([2, 3, 4])
  end

  it 'drops the oldest values beyond its capacity with <<' do
    array << 1 << 2 << 3 << 4
    expect(array).to eq([2, 3, 4])
  end

  it 'starts empty again when re-initialized' do
    array.push(1).push(2)
    array.send(:initialize, 1)
    emptied = array.to_a
    array.push(1).push(2)
    expect([emptied, array]).to eq([[], [2]])
  end

  it 'returns itself from push' do
    expect(array.push(1)).to equal(array)
  end
end
