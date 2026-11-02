# What a process's state machine does, for every state and event: where
# each event moves it, which callbacks run and in what order, and what
# halting or raising in a callback does
PROCESS_STATES = %w[unmonitored up down starting stopping restarting].freeze

describe Bluepill::Process do
  # Where each event goes from each state. A tick goes to the first state
  # when the process is running, and the second when it isn't.
  targets = {
    start: {'unmonitored' => 'starting', 'down' => 'starting'},
    stop: {'up' => 'stopping'},
    unmonitor: Hash[PROCESS_STATES.collect { |state| [state, 'unmonitored'] }],
    restart: {'up' => 'restarting', 'down' => 'restarting'},
  }
  ticks = {
    'up' => %w[up down],
    'down' => %w[up starting],
    'starting' => %w[up down],
    'stopping' => %w[up down],
    'restarting' => %w[up down],
  }

  subject(:process) { described_class.new('proc', {}, logger: double('logger').as_null_object) }

  let(:calls) { [] }
  let(:running) { true }

  before do
    allow(process).to receive(:process_running?) { running }
    allow(process).to receive(:notify_triggers) do |transition|
      calls << [:notify_triggers, transition.from_name, transition.to_name, transition.loopback?, process.state]
    end
    allow(process).to receive(:record_transition) do |transition|
      calls << [:record_transition, transition.from_name, transition.to_name, transition.loopback?, process.state]
    end
    [:clean_threads, :start_process, :stop_process, :restart_process, :run_watches, :post_start_process].each do |callback|
      allow(process).to receive(callback) { calls << [callback, process.state] }
    end
    allow(process).to receive(:notify_transition) do |transition|
      calls << [:notify_transition, transition.from_name, transition.to_name, transition.loopback?, process.state]
    end
  end

  # The callbacks a transition runs, in order
  def callbacks(from, to)
    loopback = from == to
    expected = [[:notify_triggers, from.to_sym, to.to_sym, loopback, from]]
    expected << [:clean_threads, from] if from == 'stopping'
    expected << [:start_process, to] if to == 'starting'
    expected << [:stop_process, to] if to == 'stopping'
    expected << [:restart_process, to] if to == 'restarting'
    expected << [:record_transition, from.to_sym, to.to_sym, loopback, to]
    expected << [:post_start_process, to] if to == 'up' && %w[starting restarting].include?(from)
    expected << [:notify_transition, from.to_sym, to.to_sym, loopback, to]
  end

  it 'starts unmonitored' do
    expect(process.state).to eq('unmonitored')
    expect(process).to be_unmonitored
  end

  PROCESS_STATES.each do |state|
    it "answers the predicates in #{state}" do
      process.state = state
      expect(process.state).to eq(state)
      PROCESS_STATES.each do |other|
        expect(process.public_send("#{other}?")).to be(other == state)
      end
    end
  end

  targets.each do |event, from_states|
    PROCESS_STATES.collect { |from| [from, from_states[from]] }.each do |from, to|
      if to
        it "goes from #{from} to #{to} on #{event}" do
          process.state = from
          expect(process.public_send(event)).to be true
          expect(process.state).to eq(to)
          expect(calls).to eq(callbacks(from, to))
        end
      else
        it "stays #{from} on #{event}, with no callbacks" do
          process.state = from
          expect(process.public_send(event)).to be false
          expect(process.state).to eq(from)
          expect(calls).to be_empty
        end
      end
    end
  end

  describe '#tick' do
    ticks.each do |from, (when_running, when_not)|
      [[true, when_running], [false, when_not]].each do |is_running, to|
        context "when the process #{is_running ? 'is' : "isn't"} running" do
          let(:running) { is_running }

          it "goes from #{from} to #{to}" do
            process.state = from
            process.tick
            expect(process.state).to eq(to)
            expected = callbacks(from, to)
            expected << [:run_watches, 'up'] if to == 'up'
            expect(calls).to eq(expected)
          end
        end
      end
    end

    it 'stays unmonitored, running no transition callbacks' do
      process.tick
      expect(process.state).to eq('unmonitored')
      expect(calls).to eq([[:clean_threads, 'unmonitored']])
    end
  end

  describe 'a callback that halts' do
    before do
      allow(process).to receive(:notify_triggers) { throw :halt }
    end

    it 'cancels the transition and the callbacks after it' do
      process.state = 'down'
      expect(process.start).to be false
      expect(process.state).to eq('down')
      expect(calls).to be_empty
    end

    it 'cancels a tick from stopping before it cleans up threads' do
      process.state = 'stopping'
      process.tick
      expect(process.state).to eq('stopping')
      expect(calls).to be_empty
    end
  end

  describe 'a callback that raises' do
    it 'leaves the state alone when it raises before the transition' do
      allow(process).to receive(:notify_triggers).and_raise('trigger failed')
      process.state = 'up'
      expect { process.restart }.to raise_error('trigger failed')
      expect(process.state).to eq('up')
    end

    it 'keeps the new state when it raises after the transition' do
      allow(process).to receive(:start_process).and_raise('start failed')
      expect { process.start }.to raise_error('start failed')
      expect(process.state).to eq('starting')
      expect(process).not_to have_received(:record_transition)
    end
  end

  describe 'the transition that triggers get' do
    it 'names its states as symbols' do
      transitions = []
      allow(process).to receive(:notify_triggers) { |transition| transitions << transition }
      process.state = 'up'
      process.stop
      expect(transitions.first.from_name).to eq(:up)
      expect(transitions.first.to_name).to eq(:stopping)
      expect(transitions.first.loopback?).to be false
    end
  end
end
