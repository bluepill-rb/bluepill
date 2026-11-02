# frozen_string_literal: true

describe Bluepill::Error do
  it "is a StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end

  {
    described_class => 1,
    Bluepill::ConfigError => 6,
    Bluepill::StartupError => 5,
    Bluepill::PreviousDaemonError => 4,
    Bluepill::AlreadyRunningError => 7,
    Bluepill::ConnectionError => 1,
    Bluepill::VersionMismatchError => 1,
    Bluepill::UnknownCommandError => 1,
    Bluepill::DaemonError => 8
  }.each do |error_class, status|
    it "makes the bluepill command exit with #{status} for a #{error_class.name}" do
      error = (error_class == Bluepill::DaemonError) ? error_class.new(RuntimeError.new) : error_class.new
      expect([error, error.exit_status]).to match([be_a(described_class), status])
    end
  end

  it "keeps a ConfigError's message" do
    expect(Bluepill::ConfigError.new("Config Error: bad").message).to eq("Config Error: bad")
  end
end
