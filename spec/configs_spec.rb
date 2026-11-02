# frozen_string_literal: true

require "rbconfig"

# The configs that the README and the examples show, loaded the way bluepill
# loads a config, without starting a daemon. Bluepill no longer depends on
# ActiveSupport, so 10.seconds and 100.megabytes are bluepill's own plain
# numbers here.
README_CONFIGS = File.read(File.join(BLUEPILL_ROOT, "README.md")).scan(/^```ruby\n(.*?)^```/m).flatten
  .select { |code| code.include?("Bluepill.application") }.freeze

describe "The README and example configs", type: :integration do
  let(:processes) { {} }

  before do
    app = instance_double(Bluepill::Application, pids_dir: "/tmp/pids", load: nil)
    allow(app).to receive(:add_process) { |process, _group| processes[process.name] = process }
    allow(Bluepill::Application).to receive(:new).and_return(app)
  end

  def watch(process, name)
    process.watches.detect { |w| w.name.equal?(name) }
  end

  def condition(process, name)
    watch(process, name).instance_variable_get(:@process_condition)
  end

  def every(process, name)
    watch(process, name).instance_variable_get(:@every)
  end

  def below(process, name)
    condition(process, name).instance_variable_get(:@below)
  end

  it "finds the configs in the README" do
    expect(README_CONFIGS.size).to be > 10
  end

  README_CONFIGS.each_with_index do |config, i|
    it "loads README config #{i + 1}" do
      eval(config, binding, "README.md") # rubocop:disable Security/Eval
      expect(Bluepill::Application).to have_received(:new).with("app_name", kind_of(Hash))
    end

    # A few only show the application's options, with no processes
    next unless config.include?(".process(")

    it "adds the processes of README config #{i + 1}" do
      eval(config, binding, "README.md") # rubocop:disable Security/Eval
      expect(processes).not_to be_empty
    end
  end

  it "reads durations as seconds and sizes as bytes" do
    eval(README_CONFIGS.detect { |c| c.include?(":file_time") }, binding, "README.md") # rubocop:disable Security/Eval
    process = processes.fetch("process_name")
    values = [every(process, :mem_usage), below(process, :mem_usage), below(process, :file_time)]
    expect(values).to eql([10, 104_857_600, 180])
  end

  it "reads minutes and hours" do
    eval(README_CONFIGS.detect { |c| c.include?(":running_time") }, binding, "README.md") # rubocop:disable Security/Eval
    process = processes.fetch("process_name")
    expect([every(process, :running_time), below(process, :running_time)]).to eql([600, 86_400])
  end

  it "reads grace times" do
    eval(README_CONFIGS.detect { |c| c.include?("start_grace_time = 3.seconds") }, binding, "README.md") # rubocop:disable Security/Eval
    process = processes.fetch("process_name")
    expect([process.start_grace_time, process.stop_grace_time, process.restart_grace_time]).to eql([3, 5, 8])
  end

  it "reads the delays between stop signals" do
    eval(README_CONFIGS.detect { |c| c.include?("stop_signals") }, binding, "README.md") # rubocop:disable Security/Eval
    expect(processes.fetch("process_name").stop_signals).to eql([:quit, 30, :term, 5, :kill])
  end

  it "loads the sample app, with its child limit in bytes" do
    load File.join(BLUEPILL_ROOT, "examples", "sample_app.rb")
    process = processes.fetch("forking_server")
    child = process.child_process_factory.create_child_process("child", 1, instance_double(Bluepill::Logger).as_null_object)
    values = [process.stop_grace_time, below(child, :mem_usage), process.triggers.first.within]
    expect(values).to eql([5, 52_428_800, 30])
  end

  it "loads the runit example" do
    load File.join(BLUEPILL_ROOT, "examples", "runit.rb")
    process = processes.fetch("runit-man")
    expect(condition(process, :http).instance_variable_get(:@read_timeout)).to be(3)
  end

  # ActiveSupport has to load before bluepill to be the one that defines
  # 10.seconds, so this runs in a Ruby of its own
  it "accepts the durations and sizes of a config that loads ActiveSupport" do
    script = File.join(BLUEPILL_ROOT, "spec", "support", "active_support_config.rb")
    ruby = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])
    output = IO.popen([ruby, "-I", File.join(BLUEPILL_ROOT, "lib"), script, {err: %i[child out]}], &:read)
    expect([output, $?.success?]).to match([end_with("ok\n"), true])
  end
end
