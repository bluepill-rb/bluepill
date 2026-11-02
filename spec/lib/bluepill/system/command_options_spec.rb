# frozen_string_literal: true

describe Bluepill::System::CommandOptions do
  let(:all) do
    {
      uid: "user", gid: "group", supplementary_groups: ["extra"], working_dir: "/work",
      environment: {"A" => "1"}, stdin: "in", stdout: "out", stderr: "err", timeout: 5
    }
  end

  describe "#to_h" do
    it "has each option it was made with" do
      expect(described_class.new(**all).to_h).to eq all
    end

    it "has nil for each option it wasn't given, and no environment variables" do
      expect(described_class.new.to_h).to eq(all.transform_values { nil }.merge(environment: {}))
    end
  end

  it "reads each option" do
    options = described_class.new(**all)
    expect(all.keys.to_h { |name| [name, options.public_send(name)] }).to eq all
  end

  describe "#for_hook" do
    subject(:hook) { described_class.new(**all, timeout: nil).for_hook({"B" => "2"}, 30) }

    it "adds the environment variables to the options' own" do
      expect(hook.environment).to eq("A" => "1", "B" => "2")
    end

    it "gives the hook its timeout" do
      expect(hook.timeout).to eq 30
    end

    it "keeps the other options" do
      expect(hook.to_h.except(:environment, :timeout)).to eq all.except(:environment, :timeout)
    end

    it "is a new CommandOptions" do
      expect(hook).to be_a(described_class)
    end

    it "uses the hook's environment variables without an environment of its own" do
      expect(described_class.new.for_hook({"B" => "2"}, 30).environment).to eq("B" => "2")
    end

    it "leaves the options' own environment alone" do
      options = described_class.new(**all)
      options.for_hook({"B" => "2"}, 30)
      expect(options.environment).to eq("A" => "1")
    end
  end
end
