describe Bluepill::Clock do
  # Ruby 1.9.3 and 2.0, and JRuby 1.7, have no monotonic clock
  monotonic = ::Process.respond_to?(:clock_gettime)

  describe '.now' do
    it 'reads the clock that reader chose for this Ruby' do
      expect(Bluepill::Clock::READER).to receive(:call).and_return(42)
      expect(Bluepill::Clock.now).to eq(42)
    end
  end

  describe '.reader' do
    it 'reads the system clock in whole seconds on a Ruby without clock_gettime' do
      process = double('Process')
      allow(process).to receive(:respond_to?).with(:clock_gettime).and_return(false)
      allow(Time).to receive(:now).and_return(Time.at(100.5))
      expect(Bluepill::Clock.reader(process).call).to eql(100)
    end

    if monotonic
      it 'reads the monotonic clock in whole seconds, where Ruby has it' do
        process = double('Process')
        allow(process).to receive(:respond_to?).with(:clock_gettime).and_return(true)
        allow(process).to receive(:clock_gettime).with(::Process::CLOCK_MONOTONIC).and_return(12.7)
        expect(Bluepill::Clock.reader(process).call).to eql(12)
      end

      it 'reads the monotonic clock of the Ruby it runs on by default' do
        allow(::Process).to receive(:clock_gettime).with(::Process::CLOCK_MONOTONIC).and_return(7.2)
        expect(Bluepill::Clock.reader.call).to eql(7)
      end
    else
      it 'reads the system clock of the Ruby it runs on by default' do
        allow(Time).to receive(:now).and_return(Time.at(7.2))
        expect(Bluepill::Clock.reader.call).to eql(7)
      end
    end
  end
end
