# frozen_string_literal: true

describe Bluepill::ProcessFactory::ChildFactory do
  let(:logger) { instance_double(Bluepill::Logger) }
  let(:attributes) do
    {
      start_grace_time: 1,
      stop_grace_time: 2,
      restart_grace_time: 5,
      uid: "user",
      gid: "staff",
      supplementary_groups: ["rvm"],
      working_dir: "/srv"
    }
  end
  let(:halt) { proc { self.stop_command = "halt" } }

  before { allow(::Process).to receive(:kill).with(0, 123).and_return(1) }

  def create_child(attributes, block)
    described_class.new("web", attributes, block).create_child_process("child", 123, logger)
  end

  describe "#initialize" do
    it "requires a stop command" do
      expect { described_class.new("web", attributes, proc {}) }.to raise_error(
        Bluepill::ConfigError, "Config Error: You must specify a stop_command for the children of 'web'"
      )
    end

    it "checks the children's checks" do
      config = proc { (self.stop_command = "halt") && checks(:mem_usage, below: 1, belwo: 1) }
      expect { described_class.new("web", attributes, config) }.to raise_error(ArgumentError, /belwo/)
    end

    it "gives the block only the parent's grace times, user and groups" do
      seen = []
      config = proc { (seen << attributes.dup) && self.stop_command = "halt" }
      described_class.new("web", attributes.merge(start_command: "run"), config)
      expect(seen).to eq([attributes.except(:working_dir)])
    end

    it "runs the block once, for a child without a pid" do
      runs = []
      described_class.new("web", attributes, proc { (runs << [name, actual_pid]) && self.stop_command = "halt" })
      expect(runs).to eq([["<child of web>", nil]])
    end
  end

  describe "#create_child_process" do
    it "creates a child process with the grace times, user and groups of its parent" do
      expect(create_child(attributes, halt)).to be_a(Bluepill::Process).and have_attributes(
        state: :up, name: "child", actual_pid: 123, logger:, stop_command: "halt",
        start_grace_time: 1, stop_grace_time: 2, restart_grace_time: 5,
        uid: "user", gid: "staff", supplementary_groups: ["rvm"], working_dir: nil
      )
    end

    it "gives a child the default grace times when its parent sets none" do
      child = create_child({}, halt)
      expect([child.start_grace_time, child.stop_grace_time, child.restart_grace_time]).to eq([3, 3, 3])
    end

    it "runs the block again for each child, with its pid" do
      factory = described_class.new("web", {}, proc { self.stop_command = "kill #{actual_pid.inspect}" })
      allow(::Process).to receive(:kill).with(0, 124).and_return(1)
      children = [123, 124].collect { |pid| factory.create_child_process("child", pid, logger) }
      expect(children.collect(&:stop_command)).to eq(["kill 123", "kill 124"])
    end

    it "leaves the parent's attributes as they were" do
      parent = {uid: "user"}
      factory = described_class.new("web", parent, proc { (self.uid = "other") && self.stop_command = "halt" })
      factory.create_child_process("child", 123, logger)
      expect(parent).to eq(uid: "user")
    end
  end
end
