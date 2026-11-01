describe Bluepill::ProcessConditions::MemUsage do
  subject { Bluepill::ProcessConditions::MemUsage.new(below: 100.megabytes) }

  it 'can be created without options' do
    expect(Bluepill::ProcessConditions::MemUsage.new).to be_a(Bluepill::ProcessConditions::MemUsage)
  end

  it 'stores its options' do
    expect(subject.instance_variable_get(:@options)).to eq(below: 100.megabytes)
  end

  it 'returns the memory usage of the process in kilobytes as a float' do
    expect(Bluepill::System).to receive(:memory_usage).with(123, false).and_return(2048.5)
    expect(subject.run(123, false)).to eql(2048.5)
  end

  it 'returns 0.0 for a process that ps does not list' do
    expect(Bluepill::System).to receive(:memory_usage).with(123, false).and_return(nil)
    expect(subject.run(123, false)).to eql(0.0)
  end

  describe '#check' do
    it 'passes when the usage is below the limit' do
      expect(subject.check(99 * 1024)).to be true
    end

    it 'fails when the usage is not below the limit' do
      expect(subject.check(100 * 1024)).to be false
    end

    it 'passes when the usage cannot be compared' do
      expect(subject.check(nil)).to be true
    end
  end

  describe '#format_value' do
    it 'formats values of at least one megabyte in megabytes' do
      expect(subject.format_value(1024.0)).to eq('1MB')
      expect(subject.format_value(2560.0)).to eq('3MB')
      expect(subject.format_value(10_751.0)).to eq('10MB')
    end

    it 'formats smaller values in kilobytes' do
      expect(subject.format_value(1023.0)).to eq('1023KB')
    end
  end
end
