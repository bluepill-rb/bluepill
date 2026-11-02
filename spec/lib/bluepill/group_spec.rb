describe Bluepill::Group do
  let(:logger) { instance_double(Bluepill::Logger, debug: nil) }
  let(:process_logger) { instance_double(Bluepill::Logger) }
  let(:group) { described_class.new('web', logger: logger) }

  def process_double(name, attributes = {})
    instance_double(Bluepill::Process, name, {name: name, :logger= => nil}.merge(attributes))
  end

  describe '#initialize' do
    it 'sets the name, logger and an empty process list' do
      expect(group.name).to eq('web')
      expect(group.logger).to eq(logger)
      expect(group.processes).to eq([])
    end

    it 'has no logger without options' do
      expect(described_class.new('web').logger).to be_nil
    end
  end

  describe '#add_process' do
    it 'gives the process a prefixed logger and stores it' do
      process = process_double('unicorn')
      expect(logger).to receive(:prefix_with).with('unicorn').and_return(process_logger)
      expect(process).to receive(:logger=).with(process_logger)
      group.add_process(process)
      expect(group.processes).to eq([process])
    end
  end

  context 'with processes' do
    let(:first) { process_double('first') }
    let(:second) { process_double('second') }

    before do
      allow(logger).to receive(:prefix_with).and_return(process_logger)
      group.add_process(first)
      group.add_process(second)
    end

    describe '#tick' do
      it 'ticks every process' do
        expect(first).to receive(:tick)
        expect(second).to receive(:tick)
        group.tick
      end
    end

    describe '#determine_initial_state' do
      it 'determines the initial state of every process' do
        expect(first).to receive(:determine_initial_state)
        expect(second).to receive(:determine_initial_state)
        group.determine_initial_state
      end
    end

    [:start, :unmonitor, :stop, :restart].each do |event|
      describe "##{event}" do
        let(:thread) { instance_double(Thread, join: nil) }

        before do
          allow(Thread).to receive(:new) do |&block|
            block.call
            thread
          end
        end

        it 'runs blocking commands one at a time' do
          [first, second].each do |process|
            allow(process).to receive("group_#{event}_noblock").and_return(false)
            expect(process).to receive(:handle_user_command).with(event.to_s)
          end
          expect(logger).to receive(:debug).with("Command #{event} running in blocking mode.").twice
          expect(thread).to receive(:join).twice
          expect(group.send(event)).to eq(['web:first', 'web:second'])
        end

        it 'runs non-blocking commands in parallel' do
          [first, second].each do |process|
            allow(process).to receive("group_#{event}_noblock").and_return(true)
            expect(process).to receive(:handle_user_command).with(event.to_s)
          end
          expect(logger).to receive(:debug).with("Command #{event} running in non-blocking mode.").twice
          expect(thread).to receive(:join).twice
          expect(group.send(event)).to eq(['web:first', 'web:second'])
        end

        it 'only affects the named process' do
          allow(second).to receive("group_#{event}_noblock").and_return(false)
          expect(first).not_to receive(:handle_user_command)
          expect(second).to receive(:handle_user_command).with(event.to_s)
          expect(group.send(event, 'second')).to eq(['web:second'])
        end
      end
    end

    describe '#status' do
      let(:child) { instance_double(Bluepill::Process, name: 'child', state: 'up') }

      before do
        allow(first).to receive_messages(actual_pid: 1, state: 'up', monitor_children?: true, children: [child])
        allow(second).to receive_messages(actual_pid: 2, state: 'down', monitor_children?: false)
      end

      it 'lists every process and monitored child under the group name' do
        expected = [
          'web:',
          '  first(pid:1): up',
          '    child: up',
          '  second(pid:2): down',
          '',
        ]
        expect(group.status).to eq(expected)
      end

      it 'lists processes without indentation when the group has no name' do
        group.name = nil
        expected = [
          'first(pid:1): up',
          '  child: up',
          'second(pid:2): down',
          '',
        ]
        expect(group.status).to eq(expected)
      end

      it 'lists the named process with its statistics' do
        allow(second).to receive(:statistics).and_return(instance_double(Bluepill::ProcessStatistics, to_s: 'stats'))
        expect(group.status('second')).to eq(['second(pid:2): down', 'stats', ''])
      end

      it 'lists processes after one that does not monitor children' do
        group.processes.reverse!
        expect(group.status).to eq(['web:', '  second(pid:2): down', '  first(pid:1): up', '    child: up', ''])
      end
    end
  end
end
