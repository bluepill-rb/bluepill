require 'rbconfig'

# The configs that the README and the examples show, loaded the way bluepill
# loads a config, without starting a daemon. Bluepill no longer depends on
# ActiveSupport, so 10.seconds and 100.megabytes are bluepill's own plain
# numbers here.
describe 'The README and example configs' do
  root = File.expand_path('..', File.dirname(__FILE__))
  readme = File.read(File.join(root, 'README.md'))
  configs = readme.scan(/^```ruby\n(.*?)^```/m).flatten.select { |code| code.include?('Bluepill.application') }

  let(:processes) { {} }

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
    app = double('app', pids_dir: '/tmp/pids', load: nil)
    allow(app).to receive(:add_process) { |process, _group| processes[process.name] = process }
    allow(Bluepill::Application).to receive(:new).and_return(app)
  end

  def watch(process, name)
    process.watches.detect { |w| w.name.equal?(name) }
  end

  def condition(process, name)
    watch(process, name).instance_variable_get(:@process_condition)
  end

  it 'finds the configs in the README' do
    expect(configs.size).to be > 10
  end

  configs.each_with_index do |config, i|
    it "loads README config #{i + 1}" do
      eval(config, binding, 'README.md') # rubocop:disable Security/Eval
      # A few only show the application's options, with no processes
      expect(processes).not_to be_empty if config.include?('.process(')
      expect(Bluepill::Application).to have_received(:new).with('app_name', kind_of(Hash))
    end
  end

  it 'reads durations as seconds and sizes as bytes' do
    eval(configs.detect { |c| c.include?(':file_time') }, binding, 'README.md') # rubocop:disable Security/Eval
    process = processes.fetch('process_name')
    expect(watch(process, :mem_usage).instance_variable_get(:@every)).to eql(10)
    expect(condition(process, :mem_usage).instance_variable_get(:@below)).to eql(104_857_600)
    expect(condition(process, :file_time).instance_variable_get(:@below)).to eql(180)
  end

  it 'reads minutes and hours' do
    eval(configs.detect { |c| c.include?(':running_time') }, binding, 'README.md') # rubocop:disable Security/Eval
    process = processes.fetch('process_name')
    expect(watch(process, :running_time).instance_variable_get(:@every)).to eql(600)
    expect(condition(process, :running_time).instance_variable_get(:@below)).to eql(86_400)
  end

  it 'reads grace times' do
    eval(configs.detect { |c| c.include?('start_grace_time = 3.seconds') }, binding, 'README.md') # rubocop:disable Security/Eval
    process = processes.fetch('process_name')
    expect([process.start_grace_time, process.stop_grace_time, process.restart_grace_time]).to eql([3, 5, 8])
  end

  it 'reads the delays between stop signals' do
    eval(configs.detect { |c| c.include?('stop_signals') }, binding, 'README.md') # rubocop:disable Security/Eval
    expect(processes.fetch('process_name').stop_signals).to eql([:quit, 30, :term, 5, :kill])
  end

  it 'loads the sample app, with its child limit in bytes' do
    load File.join(root, 'examples', 'sample_app.rb')
    process = processes.fetch('forking_server')
    expect(process.stop_grace_time).to eql(5)
    child_factory = process.child_process_factory
    child = child_factory.create_child_process('child', 1, double('logger').as_null_object)
    expect(condition(child, :mem_usage).instance_variable_get(:@below)).to eql(52_428_800)
    expect(process.triggers.first.within).to eql(30)
  end

  it 'loads the runit example' do
    load File.join(root, 'examples', 'runit.rb')
    process = processes.fetch('runit-man')
    expect(condition(process, :http).instance_variable_get(:@read_timeout)).to eql(3)
  end

  # ActiveSupport has to load before bluepill to be the one that defines
  # 10.seconds, so this runs in a Ruby of its own
  it 'accepts the durations and sizes of a config that loads ActiveSupport' do
    script = File.join(root, 'spec', 'support', 'active_support_config.rb')
    ruby = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])
    output = IO.popen([ruby, '-I', File.join(root, 'lib'), script, {err: [:child, :out]}], &:read)
    expect(output).to end_with("ok\n")
    expect($?).to be_success
  end
end
