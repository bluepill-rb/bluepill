describe Bluepill::Process::Watches do
  subject(:watches) { described_class.new }

  let(:logger) { instance_double(Bluepill::Logger, info: nil) }

  # A watch that's due unless told otherwise, and fires the given events
  def watch_double(name, events, due: true)
    instance_double(Bluepill::ConditionWatch, name.to_s, name: name, due?: due, run: events, to_s: "#{name}: [1, 2]")
  end

  before { watches.logger = logger }

  describe "#add" do
    it "adds a condition watch with the check's options and the logger, and returns the watches" do
      expect([watches.add(:mem_usage, below: 10, every: 10), watches.to_a]).to match(
        [be(watches), [be_a(Bluepill::ConditionWatch).and(have_attributes(name: :mem_usage, logger: logger))]]
      )
    end

    it "gives the watch its options" do
      watches.add(:mem_usage, below: 10, every: 10)
      expect(watches.first.instance_variable_get(:@every)).to eq 10
    end
  end

  describe "#<<" do
    it "adds the watch, after the others, and returns the watches" do
      first = watch_double(:first, [])
      second = watch_double(:second, [])
      expect([watches << first << second, watches.to_a]).to eq([watches, [first, second]])
    end
  end

  describe "#each" do
    it "yields each watch and returns them" do
      watch = watch_double(:watch, [])
      watches << watch
      yielded = []
      expect([watches.each { |w| yielded << w }, yielded]).to eq([[watch], [watch]])
    end
  end

  describe "#logger=" do
    let(:watch) { instance_double(Bluepill::ConditionWatch, :logger= => nil) }
    let(:new_logger) { instance_double(Bluepill::Logger) }

    before do
      watches << watch
      watches.logger = new_logger
    end

    it "sets the logger of the watches" do
      expect(watch).to have_received(:logger=).with(new_logger)
    end

    it "keeps the logger for the watches added later" do
      expect(watches.logger).to be(new_logger)
    end
  end

  describe "#clear_history!" do
    it "clears every watch's history" do
      both = [instance_double(Bluepill::ConditionWatch, clear_history!: nil), instance_double(Bluepill::ConditionWatch, clear_history!: nil)]
      both.each { |watch| watches << watch }
      watches.clear_history!
      expect(both).to all(have_received(:clear_history!))
    end
  end

  describe "#run" do
    it "returns the events each due watch fires, with the watch as the reason, in order" do
      watches << watch_double(:loud, [:restart, :stop]) << watch_double(:quiet, []) << watch_double(:other, [:start])
      expect(watches.run(100) { 5 }).to eq [[:restart, "loud: [1, 2]"], [:stop, "loud: [1, 2]"], [:start, "other: [1, 2]"]]
    end

    it "runs each due watch with the pid the block reads and the time" do
      watch = watch_double(:quiet, [])
      watches << watch
      watches.run(100) { 5 }
      expect(watch).to have_received(:run).with(5, 100)
    end

    it "checks whether each watch is due at the time" do
      watch = watch_double(:quiet, [])
      watches << watch
      watches.run(100) { 5 }
      expect(watch).to have_received(:due?).with(100)
    end

    context "with a watch that fires events and one that fires none" do
      before do
        watches << watch_double(:loud, [:restart, :stop]) << watch_double(:quiet, [])
        watches.run(100) { 5 }
      end

      it "logs the events of the watch that fires some" do
        expect(logger).to have_received(:info).once.with("loud dispatched: restart,stop")
      end

      it "logs nothing for the watch that fires none" do
        expect(logger).to have_received(:info).once
      end
    end

    it "runs each watch on a thread of its own" do
      allow(Thread).to receive(:new).and_call_original
      watches << watch_double(:first, []) << watch_double(:second, [])
      watches.run(100) { 5 }
      expect(Thread).to have_received(:new).twice
    end

    context "with no watch due" do
      let(:idle) { watch_double(:idle, [:restart], due: false) }

      before do
        allow(Thread).to receive(:new).and_call_original
        watches << idle
      end

      it "returns the same frozen empty events, without reading the pid" do
        pid_reads = 0
        events = watches.run(100) { pid_reads += 1 }
        expect([events, events.frozen?, pid_reads]).to match([be(described_class::NO_EVENTS).and(eq([])), true, 0])
      end

      it "runs no watch" do
        watches.run(100) { 5 }
        expect(idle).not_to have_received(:run)
      end

      it "starts no thread" do
        watches.run(100) { 5 }
        expect(Thread).not_to have_received(:new)
      end
    end
  end
end
