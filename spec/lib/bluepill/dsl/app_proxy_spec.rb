describe Bluepill::AppProxy do
  subject(:proxy) { described_class.new(:app_name, {}) }

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

  it 'creates an application' do
    expect(proxy.app).to eq(app)
  end

  describe '#process' do
    it 'adds a process built from the app attributes to its group' do
      proxy.working_dir = '/work'
      proxy.uid = 'user'
      proxy.process('web') do
        start_command 'run'
        group 'servers'
      end

      # The default pid file is assigned before the process block runs, so
      # it does not include a group set inside the block.
      process = be_a(Bluepill::Process).and have_attributes(
        name: 'web', working_dir: '/work', uid: 'user', pid_file: '/pids/web.pid'
      )
      expect(app).to have_received(:add_process).with(process, 'servers')
    end

    it "gives every process the app's supplementary groups, unless it sets its own" do
      groups = []
      allow(app).to receive(:add_process) { |process, _| groups << process.supplementary_groups }
      proxy.supplementary_groups = ['rvm']
      proxy.process('web') { start_command 'run' }
      proxy.process('worker') do
        start_command 'run'
        supplementary_groups ['ssl-cert']
      end

      expect(groups).to eq([['rvm'], ['ssl-cert']])
    end

    it "gives every process the app's notify_command, unless it sets its own" do
      commands = []
      allow(app).to receive(:add_process) { |process, _| commands << process.notify_command }
      proxy.notify_command = 'alert'
      proxy.process('web') { start_command 'run' }
      proxy.process('worker') do
        start_command 'run'
        notify_command 'page'
      end
      expect(commands).to eq(%w[alert page])
    end

    it 'adds a process without a group' do
      proxy.process('worker') { start_command 'run' }
      expect(app).to have_received(:add_process).with(kind_of(Bluepill::Process), nil)
    end
  end
end
