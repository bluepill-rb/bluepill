require 'tmpdir'

describe Bluepill::Application do
  let(:logger) { instance_double(Bluepill::Logger, debug: nil, err: nil, reopen: nil) }
  let(:traps) { {} }
  let(:base_dir) { Dir.mktmpdir }
  let(:foreground) { false }
  let(:app) { described_class.new('test', base_dir: base_dir, foreground: foreground) }
  let(:pids_dir) { File.join(base_dir, 'pids', 'test') }
  let(:pid_file) { File.join(base_dir, 'pids', 'test.pid') }
  let(:group) { instance_double(Bluepill::Group) }
  let(:other_group) { instance_double(Bluepill::Group) }

  before do
    allow(logger).to receive(:prefix_with).and_return(logger)
    allow(Bluepill::Logger).to receive(:new).and_return(logger)
    allow(Bluepill::ProcessJournal).to receive(:setup)
    allow(Bluepill::ProcessJournal).to receive(:logger=)
    allow(Signal).to receive(:trap) { |signal, &block| traps[signal] = block }
  end

  after { FileUtils.remove_entry(base_dir) }

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
