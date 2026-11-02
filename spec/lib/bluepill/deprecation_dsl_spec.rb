# frozen_string_literal: true

describe Bluepill::Deprecation do
  def proxy(&block)
    Bluepill::ProcessProxy.new("web", {}, block)
  end

  describe ".check_attribute" do
    it "warns about name!" do
      expect { proxy { daemonize! } }.to output(
        "DEPRECATION: bluepill 0.3.0 removes process.daemonize!. Write process.daemonize = true, which 0.2 takes too.\n"
      ).to_stderr
    end

    it "warns about name value" do
      expect { proxy { stop_command "halt" } }.to output(
        "DEPRECATION: bluepill 0.3.0 removes process.stop_command value. Write process.stop_command = value, which 0.2 takes too.\n"
      ).to_stderr
    end

    it "says nothing about name = value" do
      expect { proxy { |process| process.stop_command = "halt" } }.not_to output.to_stderr
    end

    it "says nothing about reading an attribute" do
      expect { Bluepill::ProcessProxy.new("web", {uid: "deploy"}, proc { uid }) }.not_to output.to_stderr
    end

    %i[monitor_children child_process_factory].each do |attribute|
      it "warns about setting #{attribute} in a process block" do
        expect { proxy { |process| process.public_send(:"#{attribute}=", true) } }.to output(
          "DEPRECATION: bluepill 0.3.0 doesn't let a process block set #{attribute}. " \
          "Call process.monitor_children with a block that configures the children, which 0.2 takes too.\n"
        ).to_stderr
      end
    end
  end

  describe ".check_monitor_children" do
    it "warns about monitor_children without a block" do
      expect { proxy(&:monitor_children) }.to output(
        "DEPRECATION: bluepill 0.3.0 fails the config when monitor_children has no block, " \
        "as for process 'web'. Give it a block that sets the children's stop_command.\n"
      ).to_stderr
    end

    it "says nothing about monitor_children with a block" do
      expect { proxy { |process| process.monitor_children { |child| child.stop_command = "halt" } } }.not_to output.to_stderr
    end
  end

  describe ".check_duplicate_check" do
    # A proxy with a check of each name
    def checks(*names)
      proxy { |process| names.each { |name| process.checks name, below: 5 } }
    end

    it "warns about a second check of the same name" do
      expect { checks(:cpu_usage, :cpu_usage) }.to output(
        "DEPRECATION: bluepill 0.3.0 runs every check of a process, so a process with two checks :cpu_usage runs both, " \
        "where 0.2 runs only the last. Remove the one you don't want.\n"
      ).to_stderr
    end

    it "says nothing about checks of different names" do
      expect { checks(:cpu_usage, :mem_usage) }.not_to output.to_stderr
    end
  end
end
