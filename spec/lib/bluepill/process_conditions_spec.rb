describe Bluepill::ProcessConditions do
  describe '.[]' do
    it 'looks up process conditions by name' do
      expect(described_class[:cpu_usage]).to eq(Bluepill::ProcessConditions::CpuUsage)
      expect(described_class['mem_usage']).to eq(Bluepill::ProcessConditions::MemUsage)
    end
  end
end
