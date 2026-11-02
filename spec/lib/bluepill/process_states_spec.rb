# What a process's state machine does, for every state and event: where
# each event moves it, which callbacks run and in what order, and what
# halting or raising in a callback does
PROCESS_STATES = %i[unmonitored up down starting stopping restarting].freeze

describe Bluepill::Process do
  # Where each event goes from each state. A tick goes to the first state
  # when the process is running, and the second when it isn't.
  targets = {
    start: {unmonitored: :starting, down: :starting},
    stop: {up: :stopping},
    unmonitor: Hash[PROCESS_STATES.collect { |state| [state, :unmonitored] }],
    restart: {up: :restarting, down: :restarting}
  }
  ticks = {
    up: %i[up down],
    down: %i[up starting],
    starting: %i[up down],
    stopping: %i[up down],
    restarting: %i[up down]
  }

  # The process daemonizes, so starting it doesn't wait on a timeout, and it
  # has no stop or restart command, so it's stopped with a TERM signal and
  # restarted by stopping and starting it
  subject(:process) do
    described_class.new(
      "proc", {},
      logger: instance_double(Bluepill::Logger).as_null_object, actual_pid: 123, daemonize: true,
      start_command: "start", post_start_command: "post start", notify_command: "notify"
    )
  end

  let(:calls) { [] }
  let(:running) { true }

  # Each callback is seen through what it calls: notify_triggers through a
  # trigger, clean_threads through a thread it kills, start_process through
  # System.daemonize, stop_process through the TERM signal, record_transition
  # and run_watches through a watch, and post_start_process and
  # notify_transition through the hook commands they run
  before do
    trigger = instance_double(Bluepill::Trigger)
    allow(trigger).to receive(:notify) do |transition|
      calls << [:notify_triggers, transition.from_name, transition.to_name, transition.loopback?, process.state]
    end
    process.triggers << trigger

    watch = instance_double(Bluepill::ConditionWatch, name: :watch, to_s: "watch", due?: true)
    allow(watch).to receive(:clear_history!) { calls << [:record_transition, process.state] }
    allow(watch).to receive(:run) do
      calls << [:run_watches, process.state]
      []
    end
    process.watches << watch

    thread = instance_double(Thread, join: nil)
    allow(thread).to receive(:kill) { calls << [:clean_threads, process.state] }
    process.instance_variable_get(:@threads) << thread

    allow(Thread).to receive(:new).and_wrap_original do |new, *args, &block|
      new.call(*args, &block).tap(&:join)
    end
    allow(::Process).to receive(:kill) do |signal, _pid|
      raise Errno::ESRCH unless signal != 0 || running

      calls << [:stop_process, process.state] if signal == "TERM"
      1
    end
    allow(Bluepill::ProcessJournal).to receive(:kill_all_from_journal)
    allow(Bluepill::System).to receive(:delete_if_exists)
    allow(Bluepill::System).to receive(:daemonize) do
      calls << [:start_process, process.state]
      nil
    end
    allow(Bluepill::System).to receive(:execute_blocking) do |command, options|
      env = options.fetch(:environment)
      calls << if command == "notify"
        [:notify_transition, env["BLUEPILL_FROM"], env["BLUEPILL_TO"], process.state]
      else
        [:post_start_process, process.state]
      end
      {exit_code: 0}
    end
  end

  # The callbacks a transition runs, in order. A loopback records and
  # notifies nothing. Starting cleans up threads first, and restarting stops
  # and then starts.
  def callbacks(from, to)
    expected = before_callbacks(from, to) + command_callbacks(to)
    return expected if from == to

    expected + after_callbacks(from, to)
  end

  # The callbacks before a transition: the triggers hear of it, and leaving
  # stopping cleans up threads
  def before_callbacks(from, to)
    expected = [[:notify_triggers, from, to, from == to, from]]
    expected << [:clean_threads, from] if from == :stopping
    expected
  end

  # The callbacks that start, stop or restart the process for the state it
  # reached
  def command_callbacks(to)
    case to
    when :starting then [[:clean_threads, to], [:start_process, to]]
    when :stopping then [[:stop_process, to]]
    when :restarting then [[:stop_process, to], [:clean_threads, to], [:start_process, to]]
    else []
    end
  end

  # The callbacks after a change of state: the watches forget it, a start
  # or restart that came up runs post_start_command, and then
  # notify_command runs
  def after_callbacks(from, to)
    expected = [[:record_transition, to]]
    expected << [:post_start_process, to] if to == :up && %i[starting restarting].include?(from)
    expected << [:notify_transition, from.to_s, to.to_s, to]
  end

  # The callbacks a tick runs, in order. It runs the watches once it's up.
  def tick_callbacks(from, to)
    (to == :up) ? callbacks(from, to) << %i[run_watches up] : callbacks(from, to)
  end

  # The message of what the block raises, or nil if it raises nothing
  def error_from
    yield
    nil
  rescue => e
    e.message
  end

  it "starts unmonitored" do
    expect(process).to have_attributes(state: :unmonitored, unmonitored?: true)
  end

  PROCESS_STATES.each do |state|
    it "answers the predicates in #{state}" do
      process.state = state
      predicates = PROCESS_STATES.collect { |other| process.public_send("#{other}?") }
      expect([process.state, predicates]).to eq([state, PROCESS_STATES.collect { |other| other == state }])
    end
  end

  targets.each do |event, from_states|
    PROCESS_STATES.collect { |from| [from, from_states[from]] }.each do |from, to|
      if to
        it "goes from #{from} to #{to} on #{event}" do
          process.state = from
          expect([process.public_send(event), process.state, calls]).to eq([true, to, callbacks(from, to)])
        end
      else
        it "stays #{from} on #{event}, with no callbacks" do
          process.state = from
          expect([process.public_send(event), process.state, calls]).to eq([false, from, []])
        end
      end
    end
  end

  describe "#tick" do
    ticks.each do |from, (when_running, when_not)|
      [[true, when_running], [false, when_not]].each do |is_running, to|
        context "when the process #{is_running ? "is" : "isn't"} running" do
          let(:running) { is_running }

          it "goes from #{from} to #{to}" do
            process.state = from
            process.tick
            expect([process.state, calls]).to eq([to, tick_callbacks(from, to)])
          end
        end
      end
    end

    it "stays unmonitored, running no transition callbacks" do
      process.tick
      expect([process.state, calls]).to eq([:unmonitored, [%i[clean_threads unmonitored]]])
    end
  end

  describe "a callback that halts" do
    before do
      allow(process.triggers.first).to receive(:notify) { throw :halt }
    end

    it "cancels the transition and the callbacks after it" do
      process.state = :down
      expect([process.start, process.state, calls]).to eq([false, :down, []])
    end

    it "cancels a tick from stopping before it cleans up threads" do
      process.state = :stopping
      process.tick
      expect([process.state, calls]).to eq([:stopping, []])
    end
  end

  describe "a callback that raises" do
    it "leaves the state alone when it raises before the transition" do
      allow(process.triggers.first).to receive(:notify).and_raise("trigger failed")
      process.state = :up
      expect([error_from { process.restart }, process.state]).to eq(["trigger failed", :up])
    end

    it "keeps the new state when it raises after the transition, without recording it" do
      allow(Bluepill::System).to receive(:daemonize).and_raise("start failed")
      expected = [[:notify_triggers, :unmonitored, :starting, false, :unmonitored], %i[clean_threads starting]]
      expect([error_from { process.start }, process.state, calls]).to eq(["start failed", :starting, expected])
    end
  end

  describe "the transition that triggers get" do
    it "names its states as symbols" do
      transitions = []
      allow(process.triggers.first).to receive(:notify) { |transition| transitions << transition }
      process.state = :up
      process.stop
      expect(transitions.first).to have_attributes(from_name: :up, to_name: :stopping, loopback?: false)
    end

    it "is the same frozen transition every time the state stays the same" do
      transitions = []
      allow(process.triggers.first).to receive(:notify) { |transition| transitions << transition }
      process.state = :up
      2.times { process.tick }
      expect([transitions.uniq.size, transitions.first]).to match([1, have_attributes(from_name: :up, to_name: :up, frozen?: true)])
    end
  end
end
