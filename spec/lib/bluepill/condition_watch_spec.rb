describe Bluepill::ConditionWatch do
  # What the logger logs, in order
  let(:calls) { [] }
  let(:logger) do
    logger = instance_double(Bluepill::Logger)
    [:info, :warning, :err].each do |method|
      allow(logger).to receive(method) { |message| calls << [method, message] }
    end
    logger
  end

  def watch(options = {})
    Bluepill::ConditionWatch.new(:cpu_usage, {logger: logger, every: 10, below: 50}.merge(options))
  end

  def cpu_usage(*values)
    allow(Bluepill::System).to receive(:cpu_usage).with(123, false).and_return(*values)
  end

  # What the watch fires at each tick
  def run_at(watch, *ticks)
    ticks.collect { |tick| watch.run(123, tick) }
  end

  # A condition that records its logger and options once its initialize has
  # called super
  def logging_condition(seen)
    stub_const("Bluepill::ProcessConditions::LoggingCheck", Class.new(Bluepill::ProcessConditions::ProcessCondition) do
      define_method(:initialize) do |options = {}|
        super(options)
        seen << logger << options
      end
    end)
  end

  # Record a copy of the options each CpuUsage is made with, since the
  # condition takes its logger out of them
  def record_cpu_usage_options(received)
    allow(Bluepill::ProcessConditions::CpuUsage).to receive(:new).and_wrap_original do |new, options|
      received << options.dup
      new.call(options)
    end
  end

  describe "#initialize" do
    it "gives the condition its logger while the condition's initialize runs" do
      seen = []
      logging_condition(seen)
      w = described_class.new(:logging_check, logger: logger, every: 10, below: 5)
      expect([seen, w.instance_variable_get(:@process_condition).logger]).to eq([[logger, {below: 5}], logger])
    end

    it "gives its logger to a condition whose initialize doesn't call super" do
      stub_const("Bluepill::ProcessConditions::NoSuperCheck", Class.new(Bluepill::ProcessConditions::ProcessCondition) do
        define_method(:initialize) { |_options = {}| nil }
      end)
      w = described_class.new(:no_super_check, logger: logger, every: 10)
      expect(w.instance_variable_get(:@process_condition).logger).to equal(logger)
    end

    it "exposes its name and logger" do
      expect(watch).to have_attributes(name: :cpu_usage, logger: logger)
    end

    it "passes the remaining options and its logger to the process condition" do
      received = []
      record_cpu_usage_options(received)
      watch
      expect(received).to eq([{below: 50, logger: logger}])
    end

    it "leaves the options it was given as they were" do
      options = {logger: logger, fires: :stop, every: 10, times: [2, 3], include_children: true, below: 50}
      copy = options.dup
      described_class.new(:cpu_usage, options)
      expect(options).to eq(copy)
    end

    it "passes none of its own options to the process condition" do
      received = []
      record_cpu_usage_options(received)
      watch(fires: :stop, times: [2, 3], include_children: true)
      expect(received).to eq([{below: 50, logger: logger}])
    end

    it "passes a nil logger to the process condition when it has none" do
      received = []
      record_cpu_usage_options(received)
      described_class.new(:cpu_usage, below: 50)
      expect(received).to eq([{below: 50, logger: nil}])
    end

    it "passes include_children to the process condition" do
      allow(Bluepill::System).to receive(:cpu_usage).and_return(10)
      watch(include_children: true).run(123, 0)
      expect(Bluepill::System).to have_received(:cpu_usage).with(123, true)
    end

    it "does not include children when told not to" do
      allow(Bluepill::System).to receive(:cpu_usage).and_return(10)
      watch(include_children: false).run(123, 0)
      expect(Bluepill::System).to have_received(:cpu_usage).with(123, false)
    end

    it "fires nothing when fires is nil" do
      cpu_usage(90)
      expect(watch(fires: nil).run(123, 0)).to eq([])
    end

    it "does not include children by default" do
      allow(Bluepill::System).to receive(:cpu_usage).and_return(10)
      watch.run(123, 0)
      expect(Bluepill::System).to have_received(:cpu_usage).with(123, false)
    end

    it "can be created without options" do
      expect(described_class.new(:always_true).to_s).to eq("always_true: []\n")
    end

    it "fires a restart by default and keeps only the last value" do
      cpu_usage(90, 10)
      w = watch
      expect(run_at(w, 0, 10) << w.to_s).to eq([[:restart], [], "cpu_usage: [10.0]\n"])
    end

    it "fires a single event" do
      cpu_usage(90)
      expect(watch(fires: :stop).run(123, 0)).to eq([:stop])
    end

    it "fires a list of events" do
      cpu_usage(90)
      expect(watch(fires: [:stop, :start]).run(123, 0)).to eq([:stop, :start])
    end

    it "fires the same number of times as it remembers when times is a number" do
      cpu_usage(90, 90, 10)
      w = watch(times: 2)
      expect(run_at(w, 0, 10, 20) << w.to_s).to eq([[], [:restart], [], "cpu_usage: [90.0*, 10.0]\n"])
    end

    it "fires x out of y times when times is a list" do
      cpu_usage(90, 10, 90)
      expect(run_at(watch(times: [2, 3]), 0, 10, 20)).to eq([[], [], [:restart]])
    end
  end

  describe "#due?" do
    it "is due before its first run" do
      expect(watch.due?(0)).to be true
    end

    it "is not due again until its interval has passed, and then stays due" do
      cpu_usage(10)
      w = watch
      w.run(123, 100)
      expect([w.due?(109), w.due?(110), w.due?(111)]).to eq([false, true, true])
    end
  end

  describe "#run" do
    it "fires a restart by default when the condition fails" do
      cpu_usage(90)
      expect(watch.run(123, 0)).to eq([:restart])
    end

    it "fires the configured events" do
      cpu_usage(90)
      expect(watch(fires: :stop).run(123, 0)).to eq([:stop])
    end

    it "fires nothing when the condition passes" do
      cpu_usage(10)
      expect(watch.run(123, 0)).to eq([])
    end

    it "logs the history" do
      cpu_usage(10, 90)
      run_at(watch(times: 3), 0, 10)
      expect(calls).to eq([[:info, "cpu_usage: [10.0]\n"], [:info, "cpu_usage: [10.0, 90.0*]\n"]])
    end

    it "uses the current time as the default tick" do
      cpu_usage(90)
      allow(Time).to receive(:now).and_return(Time.at(100))
      w = watch
      expect([w.run(123), w.run(123, 109), w.run(123, 110)]).to eq([[:restart], [], [:restart]])
    end

    it "fires again once the interval has passed" do
      cpu_usage(90)
      expect(run_at(watch, 0, 15)).to eq([[:restart], [:restart]])
    end

    it "checks the condition again once the interval has passed" do
      cpu_usage(90)
      run_at(watch, 0, 15)
      expect(Bluepill::System).to have_received(:cpu_usage).twice
    end

    it "keeps firing while more values fail than needed" do
      cpu_usage(90)
      expect(run_at(watch(times: [2, 3]), 0, 10, 20)).to eq([[], [:restart], [:restart]])
    end

    it "logs the formatted values" do
      allow(Bluepill::System).to receive(:memory_usage).with(123, false).and_return(2048)
      described_class.new(:mem_usage, logger: logger, every: 10, below: 1.megabyte).run(123, 0)
      expect(calls).to eq([[:info, "mem_usage: [2MB*]\n"]])
    end

    it "skips runs until the interval has passed" do
      cpu_usage(90)
      expect(run_at(watch, 0, 5)).to eq([[:restart], []])
    end

    it "does not check the condition until the interval has passed" do
      cpu_usage(90)
      run_at(watch, 0, 5)
      expect(Bluepill::System).to have_received(:cpu_usage).once
    end

    it "fires only after the condition fails the given number of times" do
      cpu_usage(90, 90, 90)
      expect(run_at(watch(times: 2), 0, 10)).to eq([[], [:restart]])
    end

    it "fires when the condition fails x out of y times" do
      cpu_usage(90, 10, 10, 90)
      w = watch(times: [2, 3])
      fired = run_at(w, 0, 10, 20, 30)
      cpu_usage(90)
      expect(fired + run_at(w, 40)).to eq([[], [], [], [], [:restart]])
    end

    it "logs and re-raises errors from the process condition" do
      error = RuntimeError.new("boom")
      error.set_backtrace(["line 1"])
      allow(Bluepill::System).to receive(:cpu_usage).and_raise(error)
      expect { watch.run(123, 0) }.to raise_error(error).and change(calls, :dup).to([[:err, ["line 1"]]])
    end

    context "when ps fails" do
      subject(:cpu_watch) { watch(times: [2, 3]) }

      before do
        cpu_usage(90)
        cpu_watch.run(123, 0)
        allow(Bluepill::System).to receive(:cpu_usage).and_raise(Bluepill::System::PsError, "Could not run ps")
      end

      it "fires nothing" do
        expect(cpu_watch.run(123, 10)).to eq([])
      end

      it "logs the failure as a warning, and nothing else" do
        cpu_watch.run(123, 10)
        expect(calls).to eq([[:info, "cpu_usage: [90.0*]\n"], [:warning, "cpu_usage: Could not run ps"]])
      end

      it "records no value" do
        cpu_watch.run(123, 10)
        expect(cpu_watch.to_s).to eq("cpu_usage: [90.0*]\n")
      end

      it "fires once the condition fails again" do
        cpu_watch.run(123, 10)
        cpu_usage(90)
        expect(cpu_watch.run(123, 20)).to eq([:restart])
      end

      it "treats a kind of ps failure the same" do
        allow(Bluepill::System).to receive(:cpu_usage).and_raise(Class.new(Bluepill::System::PsError), "Could not run ps")
        expect(cpu_watch.run(123, 10)).to eq([])
      end
    end
  end

  describe "#clear_history!" do
    it "forgets previous results" do
      cpu_usage(90)
      w = watch(times: 2)
      w.run(123, 0)
      w.clear_history!
      expect([w.to_s, w.run(123, 10)]).to eq(["cpu_usage: []\n", []])
    end

    it "remembers as many values as the second times" do
      cpu_usage(90, 10, 90)
      w = watch(times: [2, 3])
      w.clear_history!
      expect(run_at(w, 0, 10, 20)).to eq([[], [], [:restart]])
    end
  end

  describe "#logger=" do
    it "sets the logger of the watch and its condition" do
      other = instance_double(Bluepill::Logger)
      w = watch
      w.logger = other
      expect([w.logger, w.instance_variable_get(:@process_condition).logger]).to eq([other, other])
    end
  end
end
