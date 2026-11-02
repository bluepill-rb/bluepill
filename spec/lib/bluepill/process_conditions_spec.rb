# frozen_string_literal: true

describe Bluepill::ProcessConditions do
  it "has a check for each of its classes but the abstract ones" do
    names = Bluepill::CheckRegistry.names
    built_in = %w[always_true cpu_usage file_time http mem_usage running_time zombie_process]
    expect(built_in.map { |name| names.include?(name) }).to all(be true)
  end

  it "has no check for the abstract classes" do
    expect(Bluepill::CheckRegistry.names & %w[process_condition below_threshold]).to eq([])
  end
end
