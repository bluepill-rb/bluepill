# frozen_string_literal: true

describe Bluepill::Group do
  # What the processes, the logger and the command threads are told to do,
  # in order
  let(:calls) { [] }
  let(:logger) do
    logger = instance_double(Bluepill::Logger)
    prefixed = Hash.new { |loggers, name| loggers[name] = instance_double(Bluepill::Logger, "#{name} logger") }
    allow(logger).to receive(:prefix_with) { |name| prefixed[name] }
    allow(logger).to receive(:debug) { |message| calls << [:debug, message] }
    logger
  end
  let(:group) { described_class.new("web", logger: logger) }

  # A process that records what it's told to do as [method, name, *args]
  def process_double(name)
    process = instance_double(Bluepill::Process, name, name: name)
    %i[logger= tick determine_initial_state handle_user_command].each do |method|
      allow(process).to receive(method) { |*args| calls << [method, name, *args] }
    end
    process
  end

  describe "#initialize" do
    it "sets the name, logger and an empty process list" do
      expect(group).to have_attributes(name: "web", logger: logger, processes: [])
    end

    it "has no logger without options" do
      expect(described_class.new("web").logger).to be_nil
    end
  end

  describe "#add_process" do
    it "gives the process a prefixed logger and stores it" do
      process = process_double("unicorn")
      group.add_process(process)
      expect([calls, group.processes]).to eq([[[:logger=, "unicorn", logger.prefix_with("unicorn")]], [process]])
    end
  end

  context "with processes" do
    let(:processes) { [process_double("first"), process_double("second")] }

    before do
      processes.each { |process| group.add_process(process) }
      calls.clear
    end

    describe "#tick" do
      it "ticks every process" do
        group.tick
        expect(calls).to eq([[:tick, "first"], [:tick, "second"]])
      end

      # A real process whose state machine raises, or records its events
      def real_process(name, broken)
        process = Bluepill::Process.new(name, [])
        if broken
          allow(process).to receive(:fire_event).and_raise("boom")
        else
          allow(process).to receive(:fire_event) { |event| calls << [event, name] }
        end
        process
      end

      it "ticks the other processes when one raises" do
        group = described_class.new("web", logger: instance_double(Bluepill::Logger).as_null_object)
        group.add_process(real_process("broken", true))
        group.add_process(real_process("healthy", false))
        group.tick
        expect(calls).to eq([[:tick, "healthy"]])
      end
    end

    describe "#determine_initial_state" do
      it "determines the initial state of every process" do
        group.determine_initial_state
        expect(calls).to eq([[:determine_initial_state, "first"], [:determine_initial_state, "second"]])
      end
    end

    %i[start unmonitor stop restart].each do |event|
      describe "##{event}" do
        let(:thread) do
          thread = instance_double(Thread)
          allow(thread).to receive(:join) { calls << [:join] }
          thread
        end

        before do
          allow(Thread).to receive(:new) do |&block|
            block.call
            thread
          end
        end

        # Make the processes run the event's command blocking or not
        def noblock(event, value, targets = processes)
          targets.each { |process| allow(process).to receive("group_#{event}_noblock").and_return(value) }
        end

        # What running the event's command on a process logs and calls
        def command(event, mode, name)
          [[:debug, "Command #{event} running in #{mode} mode."], [:handle_user_command, name, event]]
        end

        it "runs blocking commands one at a time" do
          noblock(event, false)
          expected = command(event, "blocking", "first") + [[:join]] + command(event, "blocking", "second") + [[:join]]
          expect([group.send(event), calls]).to eq([["web:first", "web:second"], expected])
        end

        it "runs non-blocking commands in parallel" do
          noblock(event, true)
          expected = command(event, "non-blocking", "first") + command(event, "non-blocking", "second") + [[:join], [:join]]
          expect([group.send(event), calls]).to eq([["web:first", "web:second"], expected])
        end

        it "only affects the named process" do
          noblock(event, false, [processes.last])
          expect([group.send(event, "second"), calls]).to eq([["web:second"], command(event, "blocking", "second") + [[:join]]])
        end
      end
    end

    describe "#status" do
      let(:child) { instance_double(Bluepill::Process, name: "child", state: :up) }

      before do
        allow(processes.first).to receive_messages(actual_pid: 1, state: :up, monitor_children?: true, children: [child])
        allow(processes.last).to receive_messages(actual_pid: 2, state: :down, monitor_children?: false)
      end

      it "lists every process and monitored child under the group name" do
        expect(group.status).to eq(["web:", "  first(pid:1): up", "    child: up", "  second(pid:2): down", ""])
      end

      it "lists processes without indentation when the group has no name" do
        group.name = nil
        expect(group.status).to eq(["first(pid:1): up", "  child: up", "second(pid:2): down", ""])
      end

      it "lists the named process with its statistics" do
        allow(processes.last).to receive(:statistics).and_return(instance_double(Bluepill::ProcessStatistics, to_s: "stats"))
        expect(group.status("second")).to eq(["second(pid:2): down", "stats", ""])
      end

      it "lists processes after one that does not monitor children" do
        group.processes.reverse!
        expect(group.status).to eq(["web:", "  second(pid:2): down", "  first(pid:1): up", "    child: up", ""])
      end
    end
  end
end
