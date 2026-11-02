describe Bluepill::ProcessProxy do
  describe '#initialize' do
    it 'evaluates a block without arguments in the context of the proxy' do
      context = nil
      proxy = Bluepill::ProcessProxy.new('web', {}, proc { context = self })
      expect(context).to eq(proxy)
    end

    it 'yields the proxy to a block with one argument' do
      yielded = nil
      proxy = Bluepill::ProcessProxy.new('web', {}, proc { |p| yielded = p })
      expect(yielded).to eq(proxy)
    end

    it 'exposes its name and attributes' do
      attributes = {uid: 'user'}
      proxy = Bluepill::ProcessProxy.new('web', attributes, proc {})
      expect(proxy.name).to eq('web')
      expect(proxy.attributes).to equal(attributes)
      expect(proxy.watches).to eq({})
    end
  end

  describe 'attribute DSL' do
    it 'sets attributes with a setter' do
      proxy = Bluepill::ProcessProxy.new('web', {}, proc { |p| p.start_command = 'run' })
      expect(proxy.attributes).to eq(start_command: 'run')
    end

    it 'sets attributes with a single argument' do
      proxy = Bluepill::ProcessProxy.new('web', {}, proc { stop_command 'halt' })
      expect(proxy.attributes).to eq(stop_command: 'halt')
    end

    it 'sets attributes to true with a bang method' do
      proxy = Bluepill::ProcessProxy.new('web', {}, proc { daemonize! })
      expect(proxy.attributes).to eq(daemonize: true)
    end

    it 'responds to setters, bang methods and attributes that have been set' do
      proxy = Bluepill::ProcessProxy.new('web', {uid: 'user'}, proc {})
      expect(proxy).to respond_to(:start_command=)
      expect(proxy).to respond_to(:daemonize!)
      expect(proxy).to respond_to(:uid)
      expect(proxy).not_to respond_to(:gid)
    end

    it 'reads attributes that have been set' do
      value = nil
      Bluepill::ProcessProxy.new('web', {}, proc do
        start_command 'run'
        value = start_command
      end)
      expect(value).to eq('run')
    end

    def unknown(name)
      "DEPRECATION: bluepill 0.2.0 fails the config on the process attribute '#{name}', which bluepill doesn't know, " \
        "where 0.1 ignores it. Remove it, or fix its name.\n"
    end

    it 'warns, once for each, about an attribute that bluepill 0.2.0 does not know, and sets it' do
      proxy = nil
      expect do
        proxy = Bluepill::ProcessProxy.new('web', {}, proc do |p|
          p.start_comand = 'run'
          p.start_comand = 'again'
          p.stop_comand 'halt'
          p.demonize!
        end)
      end.to output(unknown(:start_comand) + unknown(:stop_comand) + unknown(:demonize)).to_stderr
      expect(proxy.attributes).to eq(start_comand: 'again', stop_comand: 'halt', demonize: true)
    end

    it 'does not warn about the attributes that bluepill 0.2.0 knows' do
      expect do
        Bluepill::ProcessProxy.new('web', {}, proc do |p|
          p.start_command = 'run'
          p.group = 'servers'
          p.hook_timeout = 60
          p.daemonize!
        end)
      end.not_to output.to_stderr
    end

    it 'raises NameError for unknown attributes without arguments' do
      expect { Bluepill::ProcessProxy.new('web', {}, proc { start_command }) }.to raise_error(NameError)
    end

    it 'raises NoMethodError when called with several arguments' do
      expect { Bluepill::ProcessProxy.new('web', {}, proc { start_command 'a', 'b' }) }.to raise_error(NoMethodError)
    end
  end

  describe '#checks' do
    it 'records a watch with its options' do
      proxy = Bluepill::ProcessProxy.new('web', {}, proc do
        checks :cpu_usage, every: 10, below: 5
        checks :always_true
      end)
      expect(proxy.watches).to eq(cpu_usage: {every: 10, below: 5}, always_true: {})
    end
  end

  describe '#monitor_children' do
    it 'stores the child process block' do
      child_block = proc {}
      proxy = Bluepill::ProcessProxy.new('web', {}, proc { |p| p.monitor_children(&child_block) })
      expect(proxy.attributes).to eq(monitor_children: true, child_process_block: child_block)
    end
  end

  describe '#to_process' do
    it 'builds a process from its watches and attributes' do
      proxy = Bluepill::ProcessProxy.new('web', {}, proc do
        start_command 'run'
        checks :always_true, every: 10
      end)
      process = proxy.to_process
      expect(process).to be_a(Bluepill::Process)
      expect(process.name).to eq('web')
      expect(process.start_command).to eq('run')
      expect(process.watches.size).to eq(1)
    end
  end

  describe '.known_in_0_2?' do
    it 'knows the attributes of a process' do
      Bluepill::Process::CONFIGURABLE_ATTRIBUTES.each do |name|
        expect(Bluepill::ProcessProxy.known_in_0_2?(name)).to be(true)
      end
    end

    it 'knows the group and the hooks that bluepill 0.2.0 adds' do
      [:group, :post_start_command, :pre_stop_command, :post_stop_command, :notify_command, :hook_timeout].each do |name|
        expect(Bluepill::ProcessProxy.known_in_0_2?(name)).to be(true)
      end
    end

    it 'knows no other attribute' do
      expect(Bluepill::ProcessProxy.known_in_0_2?(:start_comand)).to be(false)
      expect(Bluepill::ProcessProxy.known_in_0_2?('start_command')).to be(false)
      expect(Bluepill::ProcessProxy.known_in_0_2?(:child_process_block)).to be(false)
    end
  end
end
