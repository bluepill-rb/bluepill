# frozen_string_literal: true

describe Bluepill::ProcessConditions do
  describe ".[]" do
    it "looks up process conditions by name" do
      expect([described_class[:cpu_usage], described_class["mem_usage"]]).to eq(
        [Bluepill::ProcessConditions::CpuUsage, Bluepill::ProcessConditions::MemUsage]
      )
    end

    it "has no check named below, which a config uses as an option" do
      expect { described_class[:below] }.to raise_error(NameError)
    end
  end
end
