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

    it 'reads attributes that have been set' do
      value = nil
      Bluepill::ProcessProxy.new('web', {}, proc do
        start_command 'run'
        value = start_command
      end)
      expect(value).to eq('run')
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
end
