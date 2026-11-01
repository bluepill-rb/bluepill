describe Bluepill::ProcessConditions do
  describe '.[]' do
    it 'looks up process conditions by name' do
      expect(Bluepill::ProcessConditions[:cpu_usage]).to eq(Bluepill::ProcessConditions::CpuUsage)
      expect(Bluepill::ProcessConditions['mem_usage']).to eq(Bluepill::ProcessConditions::MemUsage)
    end
  end
end
