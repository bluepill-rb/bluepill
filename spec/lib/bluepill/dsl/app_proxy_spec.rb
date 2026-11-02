# frozen_string_literal: true

describe Bluepill::AppProxy do
  subject(:proxy) { described_class.new(:app_name, {}) }

  let(:app) { instance_double(Bluepill::Application, pids_dir: "/pids", add_process: nil) }

  before do
    allow(Bluepill::Application).to receive(:new).with("app_name", {}).and_return(app)
    # Silence the warning for processes without a known pid
    allow($stderr).to receive(:puts)
  end

  it "creates an application" do
    expect(proxy.app).to eq(app)
  end

  describe "#process" do
    # Add a process that keeps the app's value of an attribute and one that
    # sets its own, and return the value each process ends up with
    def added(attribute, own_value)
      values = []
      allow(app).to receive(:add_process) { |process, _| values << process.public_send(attribute) }
      proxy.process("web") { self.start_command = "run" }
      proxy.process("worker") do
        self.start_command = "run"
        public_send(attribute, own_value)
      end
      values
    end

    context "with app attributes and a group" do
      before do
        proxy.working_dir = "/work"
        proxy.uid = "user"
        proxy.process("web") do
          self.start_command = "run"
          self.group = "servers"
        end
      end

      it "adds a process built from the app attributes to its group" do
        # The default pid file is assigned before the process block runs, so
        # it does not include a group set inside the block.
        process = be_a(Bluepill::Process).and have_attributes(
          name: "web", working_dir: "/work", uid: "user", pid_file: "/pids/web.pid"
        )
        expect(app).to have_received(:add_process).with(process, "servers")
      end
    end

    it "gives every process the app's supplementary groups, unless it sets its own" do
      proxy.supplementary_groups = ["rvm"]
      expect(added(:supplementary_groups, ["ssl-cert"])).to eq([["rvm"], ["ssl-cert"]])
    end

    it "gives every process the app's notify_command, unless it sets its own" do
      proxy.notify_command = "alert"
      expect(added(:notify_command, "page")).to eq(%w[alert page])
    end

    it "rejects a second process with the same name" do
      proxy.process("web") { self.start_command = "run" }
      expect { proxy.process("web") { self.start_command = "run" } }
        .to raise_error(SystemExit).and output("Config Error: You have two entries for the process name 'web'\n").to_stderr
    end

    it "checks its processes apart from another application's" do
      proxy.process("web") { self.start_command = "run" }
      other = described_class.new(:app_name, {})
      other.process("web") { self.start_command = "run" }
      expect(app).to have_received(:add_process).twice
    end

    it "adds a process without a group" do
      proxy.process("worker") { self.start_command = "run" }
      expect(app).to have_received(:add_process).with(kind_of(Bluepill::Process), nil)
    end
  end
end
