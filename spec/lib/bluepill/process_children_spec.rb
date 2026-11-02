# frozen_string_literal: true

require_relative "../../support/process_context"

describe Bluepill::Process do
  include_context "with a process"

  describe "#refresh_children!" do
    let(:factory) { instance_double(Bluepill::ProcessFactory::ChildFactory, "factory") }
    let(:child_logger) { instance_double(Bluepill::Logger, "child logger") }

    before do
      process.actual_pid = 5
      process.child_process_factory = factory
      allow(logger).to receive(:prefix_with).and_return(child_logger)
    end

    context "with dead, living and new children" do
      let(:kids) do
        {
          dead: instance_double(described_class, "dead", actual_pid: 6),
          alive: instance_double(described_class, "alive", actual_pid: 7),
          other: instance_double(described_class, "other", actual_pid: 9, process_running?: true),
          new: instance_double(described_class, "new child")
        }
      end

      before do
        process.children.concat(kids.values_at(:dead, :alive, :other))
        allow(kids[:dead]).to receive(:process_running?).with(true).and_return(false)
        allow(kids[:alive]).to receive(:process_running?).with(true).and_return(true)
        allow(Bluepill::System).to receive(:get_children).with(5).and_return([7, 8, 9])
        allow(factory).to receive(:create_child_process).with("<child(pid:8)>", 8, child_logger).and_return(kids[:new])
        process.refresh_children!
      end

      it "prunes dead children and adds new ones" do
        expect(process.children).to eq kids.values_at(:alive, :other, :new)
      end

      it "logs the children it has and finds" do
        expect(logger).to have_received(:info).with("Existing children: 7,9. Got new children: [8] for 5")
      end

      it "prefixes the new child's logger with its name" do
        expect(logger).to have_received(:prefix_with).with("<child(pid:8)>")
      end

      it "journals no children when not daemonized" do
        expect(journal).not_to have_received(:append).with(8)
      end
    end

    it "journals new children when daemonized" do
      process.daemonize = true
      allow(Bluepill::System).to receive(:get_children).and_return([8])
      allow(factory).to receive(:create_child_process).and_return(instance_double(described_class, "child"))
      process.refresh_children!
      expect(journal).to have_received(:append).with(8)
    end

    context "without new children" do
      before do
        allow(Bluepill::System).to receive(:get_children).and_return([])
        process.refresh_children!
      end

      it "logs nothing" do
        expect(logger).not_to have_received(:info)
      end

      it "adds no children" do
        expect(process.children).to be_empty
      end
    end
  end
end
