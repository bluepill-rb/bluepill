describe Bluepill::AppProxy do
  let(:app) { instance_double(Bluepill::Application, pids_dir: '/pids', add_process: nil) }

  around do |example|
    process_keys = Bluepill::ProcessFactory.class_variable_get(:@@process_keys)
    pid_files = Bluepill::ProcessFactory.class_variable_get(:@@pid_files)
    Bluepill::ProcessFactory.class_variable_set(:@@process_keys, {})
    Bluepill::ProcessFactory.class_variable_set(:@@pid_files, {})
    begin
      example.run
    ensure
      Bluepill::ProcessFactory.class_variable_set(:@@process_keys, process_keys)
      Bluepill::ProcessFactory.class_variable_set(:@@pid_files, pid_files)
    end
  end

  before do
    allow(Bluepill::Application).to receive(:new).with('app_name', {}).and_return(app)
    # Silence the warning for processes without a known pid
    allow($stderr).to receive(:puts)
  end

  subject { Bluepill::AppProxy.new(:app_name, {}) }

  it 'creates an application' do
    expect(subject.app).to eq(app)
  end

  describe '#process' do
    it 'adds a process built from the app attributes to its group' do
      subject.working_dir = '/work'
      subject.uid = 'user'
      subject.process('web') do
        start_command 'run'
        group 'servers'
      end

      expect(app).to have_received(:add_process) do |process, group|
        expect(process).to be_a(Bluepill::Process)
        expect(process.name).to eq('web')
        expect(process.working_dir).to eq('/work')
        expect(process.uid).to eq('user')
        # The default pid file is assigned before the process block runs, so
        # it does not include a group set inside the block.
        expect(process.pid_file).to eq('/pids/web.pid')
        expect(group).to eq('servers')
      end
    end

    it "gives every process the app's supplementary groups, unless it sets its own" do
      groups = []
      allow(app).to receive(:add_process) { |process, _| groups << process.supplementary_groups }
      subject.supplementary_groups = ['rvm']
      subject.process('web') { start_command 'run' }
      subject.process('worker') do
        start_command 'run'
        supplementary_groups ['ssl-cert']
      end

      expect(groups).to eq([['rvm'], ['ssl-cert']])
    end

    it 'adds a process without a group' do
      subject.process('worker') { start_command 'run' }
      expect(app).to have_received(:add_process).with(kind_of(Bluepill::Process), nil)
    end
  end
end
