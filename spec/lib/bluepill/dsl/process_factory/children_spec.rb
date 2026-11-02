# frozen_string_literal: true

describe Bluepill::ProcessFactory::Children do
  describe "#check_children" do
    def create(&child_block)
      parent = proc do |process|
        process.daemonize = true
        process.start_command = "server"
        process.monitor_children(&child_block)
      end
      Bluepill::ProcessFactory.new({}, parent).create_process("web", "/pids")
    end

    it "warns about a block that sets no stop_command" do
      expect { create { |child| child.checks :mem_usage, below: 5 } }.to output(
        "DEPRECATION: bluepill 0.3.0 fails the config when a monitor_children block sets no stop_command, " \
        "as for the children of 'web', where 0.2 exits the daemon when it first finds a child. " \
        "Set the children's stop_command in the block.\n"
      ).to_stderr
    end

    it "says nothing about a block that sets one" do
      expect { create { |child| child.stop_command = "kill {{PID}}" } }.not_to output.to_stderr
    end

    it "warns about the children's on_start_timeout" do
      expect { create { |child| (child.stop_command = "halt") && (child.on_start_timeout = "stop") } }.to output(
        /process '<child of web>''s on_start_timeout of "stop"/
      ).to_stderr
    end

    it "warns about the children's checks" do
      expect { create { |child| (child.stop_command = "halt") && child.checks(:mem_usage, below: 5, evry: 5) } }.to output(/option evry:/).to_stderr
    end

    it "warns about nothing for a block that raises for a child without a pid" do
      expect { create { |_child| raise "no pid" } }.not_to output.to_stderr
    end

    it "warns about nothing without a block" do
      factory = Bluepill::ProcessFactory.new({}, nil)
      expect { factory.check_children("web") }.not_to output.to_stderr
    end
  end
end
