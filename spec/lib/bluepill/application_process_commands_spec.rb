describe Bluepill::Application do
  let(:app) { described_class.new('test', base_dir: '/var/bluepill') }
  let(:group) { instance_double(Bluepill::Group) }
  let(:other_group) { instance_double(Bluepill::Group) }

  before do
    logger = instance_double(Bluepill::Logger)
    allow(logger).to receive(:prefix_with).and_return(logger)
    allow(Bluepill::Logger).to receive(:new).and_return(logger)
    allow(Bluepill::ProcessJournal).to receive(:setup)
    allow(Bluepill::ProcessJournal).to receive(:logger=)
    # Don't trap the specs' own signals
    allow(Signal).to receive(:trap)
    # Don't make /var/bluepill's directories
    allow(FileUtils).to receive_messages(mkdir_p: nil, chmod: nil)
  end

  describe 'process commands' do
    before { app.groups = {'web' => group, 'db' => other_group} }

    described_class::PROCESS_COMMANDS.each do |command|
      describe "##{command}" do
        it 'is sent to every group without arguments' do
          allow(group).to receive(command).with(no_args).and_return(['web:a'])
          allow(other_group).to receive(command).with(no_args).and_return(['db:b'])
          expect(app.send(command)).to eq(['web:a', 'db:b'])
        end

        it 'is sent to the named group' do
          allow(group).to receive(command).with('a').and_return(['web:a'])
          expect(app.send(command, 'web', 'a')).to eq(['web:a'])
        end

        it 'is sent to every group for a process name' do
          allow(group).to receive(command).with('a').and_return(['web:a'])
          allow(other_group).to receive(command).with('a').and_return(['db:a'])
          expect(app.send(command, 'a')).to eq(['web:a', 'db:a'])
        end

        it 'is sent to every group for a process name containing a colon' do
          allow(group).to receive(command).with('job:a').and_return(['web:job:a'])
          allow(other_group).to receive(command).with('job:a').and_return(['db:job:a'])
          expect(app.send(command, 'job', 'a')).to eq(['web:job:a', 'db:job:a'])
        end

        it 'is sent to every group for a process name without a group' do
          allow(group).to receive(command).with('a').and_return(['web:a'])
          allow(other_group).to receive(command).with('a').and_return(['db:a'])
          expect(app.send(command, nil, 'a')).to eq(['web:a', 'db:a'])
        end

        it 'prefers the named group over a process name containing a colon' do
          allow(group).to receive(command).with('job:a').and_return(['web:job:a'])
          expect(app.send(command, 'web', 'job:a')).to eq(['web:job:a'])
        end

        it 'is not sent to the other groups when a group is named' do
          allow(group).to receive(command).and_return([])
          allow(other_group).to receive(command)
          app.send(command, 'web', 'job:a')
          expect(other_group).not_to have_received(command)
        end
      end
    end
  end
end
