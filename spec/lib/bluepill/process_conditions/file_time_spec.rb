require 'tmpdir'

describe Bluepill::ProcessConditions::FileTime do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:filename) { File.join(@dir, 'heartbeat') }

  subject { Bluepill::ProcessConditions::FileTime.new(below: 60, filename: filename) }

  describe '#run' do
    it 'returns the time since the file was modified' do
      File.open(filename, 'w') {}
      mtime = File.mtime(filename)
      allow(Time).to receive(:now).and_return(mtime + 30)
      expect(subject.run(123, false)).to eq(30)
    end

    it 'returns nil when the file does not exist' do
      expect(subject.run(123, false)).to be_nil
    end

    it 'returns the error when the file cannot be read' do
      error = Errno::EACCES.new(filename)
      allow(File).to receive(:exist?).with(filename).and_return(true)
      allow(File).to receive(:mtime).with(filename).and_raise(error)
      expect(subject.run(123, false)).to eq(error)
    end
  end

  describe '#check' do
    it 'fails when there is no value' do
      expect(subject.check(nil)).to be false
    end

    it 'passes when the file was modified recently' do
      expect(subject.check(59)).to be true
    end

    it 'fails when the file was not modified recently' do
      expect(subject.check(60)).to be false
    end
  end
end
