# frozen_string_literal: true

describe Bluepill::Process::Attributes do
  subject(:attributes) { Class.new { include Bluepill::Process::Attributes }.new }

  describe "#configure" do
    it "sets the defaults" do
      attributes.configure({})
      expect(described_class::DEFAULTS.keys.to_h { |name| [name, attributes.public_send(name)] }).to eq(described_class::DEFAULTS)
    end

    it "sets the options it's given, over the defaults" do
      attributes.configure(start_grace_time: 10, start_command: "run")
      expect([attributes.start_grace_time, attributes.stop_grace_time, attributes.start_command]).to eq([10, 3, "run"])
    end

    it "keeps an option set to nil or false" do
      attributes.configure(environment: nil, cache_actual_pid: false)
      expect([attributes.environment, attributes.cache_actual_pid]).to eq([nil, false])
    end

    it "leaves the attributes without a default unset" do
      attributes.configure({})
      expect([attributes.start_command, attributes.pid_file, attributes.auto_start]).to all(be_nil)
    end

    it "rejects options it doesn't have, naming them" do
      expect { attributes.configure(group: "servers", start_command: "run", foo: 1) }
        .to raise_error(ArgumentError, "unknown attributes: :group, :foo")
    end
  end

  describe "DEFAULTS" do
    it "is frozen, with a frozen environment" do
      expect([described_class::DEFAULTS, described_class::DEFAULTS.fetch(:environment)]).to all(be_frozen)
    end

    it "only has attributes a config can set" do
      expect(described_class::DEFAULTS.keys - described_class::CONFIGURABLE_ATTRIBUTES).to be_empty
    end
  end

  it "lets a process inherit only attributes a config can set from its app and its parent" do
    expect(described_class::APP_ATTRIBUTES + described_class::CHILD_ATTRIBUTES - described_class::CONFIGURABLE_ATTRIBUTES).to be_empty
  end
end
