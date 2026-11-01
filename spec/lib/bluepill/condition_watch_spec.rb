describe Bluepill::ConditionWatch do
  let(:logger) { instance_double(Bluepill::Logger, info: nil, warning: nil, err: nil) }

  def watch(options = {})
    Bluepill::ConditionWatch.new(:cpu_usage, {logger: logger, every: 10, below: 50}.merge(options))
  end

  def cpu_usage(*values)
    allow(Bluepill::System).to receive(:cpu_usage).with(123, false).and_return(*values)
  end

  describe '#initialize' do
    it 'exposes its name and logger' do
      w = watch
      expect(w.name).to eq(:cpu_usage)
      expect(w.logger).to eq(logger)
    end

    it 'passes the remaining options to the process condition' do
      options = {below: 50}
      expect(Bluepill::ProcessConditions::CpuUsage).to receive(:new).with(options).and_call_original
      watch
    end

    it 'passes include_children to the process condition' do
      expect(Bluepill::System).to receive(:cpu_usage).with(123, true).and_return(10)
      watch(include_children: true).run(123, 0)
    end
  end

  describe '#run' do
    it 'fires a restart by default when the condition fails' do
      cpu_usage(90)
      expect(watch.run(123, 0)).to eq([:restart])
    end

    it 'fires the configured events' do
      cpu_usage(90)
      expect(watch(fires: :stop).run(123, 0)).to eq([:stop])
    end

    it 'fires nothing when the condition passes' do
      cpu_usage(10)
      expect(watch.run(123, 0)).to eq([])
    end

    it 'logs the history' do
      cpu_usage(10, 90)
      w = watch(times: 3)
      w.run(123, 0)
      w.run(123, 10)
      expect(logger).to have_received(:info).with("cpu_usage: [10.0, 90.0*]\n")
    end

    it 'uses the current time as the default tick' do
      cpu_usage(90)
      allow(Time).to receive(:now).and_return(Time.at(100))
      w = watch
      expect(w.run(123)).to eq([:restart])
      expect(w.run(123, 109)).to eq([])
      expect(w.run(123, 110)).to eq([:restart])
    end

    it 'skips runs until the interval has passed' do
      cpu_usage(90)
      w = watch
      w.run(123, 0)
      expect(w.run(123, 5)).to eq([])
      expect(Bluepill::System).to have_received(:cpu_usage).once
    end

    it 'fires only after the condition fails the given number of times' do
      cpu_usage(90, 90, 90)
      w = watch(times: 2)
      expect(w.run(123, 0)).to eq([])
      expect(w.run(123, 10)).to eq([:restart])
    end

    it 'fires when the condition fails x out of y times' do
      cpu_usage(90, 10, 10, 90)
      w = watch(times: [2, 3])
      expect(w.run(123, 0)).to eq([])
      expect(w.run(123, 10)).to eq([])
      expect(w.run(123, 20)).to eq([])
      expect(w.run(123, 30)).to eq([])
      cpu_usage(90)
      expect(w.run(123, 40)).to eq([:restart])
    end

    it 'logs and re-raises errors from the process condition' do
      error = RuntimeError.new('boom')
      error.set_backtrace(['line 1'])
      allow(Bluepill::System).to receive(:cpu_usage).and_raise(error)
      expect { watch.run(123, 0) }.to raise_error(error)
      expect(logger).to have_received(:err).with(['line 1'])
    end

    it 'logs a ps failure and skips the check without recording a value' do
      cpu_usage(90)
      w = watch(times: [2, 3])
      w.run(123, 0)
      allow(Bluepill::System).to receive(:cpu_usage).and_raise(Bluepill::System::PsError, 'Could not run ps')
      expect(w.run(123, 10)).to eq([])
      expect(logger).to have_received(:warning).with('cpu_usage: Could not run ps')
      expect(logger).not_to have_received(:err)
      expect(w.to_s).to eq("cpu_usage: [90.0*]\n")
      cpu_usage(90)
      expect(w.run(123, 20)).to eq([:restart])
    end
  end

  describe '#clear_history!' do
    it 'forgets previous results' do
      cpu_usage(90)
      w = watch(times: 2)
      w.run(123, 0)
      w.clear_history!
      expect(w.to_s).to eq("cpu_usage: []\n")
      expect(w.run(123, 10)).to eq([])
    end
  end
end
