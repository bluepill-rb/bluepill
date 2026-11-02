# frozen_string_literal: true

describe Bluepill::ProcessProxy do
  describe "#initialize" do
    it "evaluates a block without arguments in the context of the proxy" do
      context = nil
      proxy = described_class.new("web", {}, proc { context = self })
      expect(context).to eq(proxy)
    end

    it "yields the proxy to a block with one argument" do
      yielded = nil
      proxy = described_class.new("web", {}, proc { |p| yielded = p })
      expect(yielded).to eq(proxy)
    end

    it "exposes its name and attributes" do
      proxy = described_class.new("web", {uid: "user"}, proc {})
      expect(proxy).to have_attributes(name: "web", attributes: {uid: "user"}, actual_pid: nil, child_process_block: nil)
    end

    it "exposes the pid of a child" do
      expect(described_class.new("child", {}, proc {}, actual_pid: 5).actual_pid).to eq(5)
    end

    it "leaves the attributes it was given as they were" do
      attributes = {uid: "user"}
      described_class.new("web", attributes, proc { |p| p.uid = "other" })
      expect(attributes).to eq(uid: "user")
    end

    it "starts with no checks" do
      allow(Bluepill::Process).to receive(:new)
      described_class.new("web", {}, proc {}).to_process
      expect(Bluepill::Process).to have_received(:new).with("web", [], actual_pid: nil)
    end
  end

  describe "attribute DSL" do
    it "sets attributes with a setter" do
      proxy = described_class.new("web", {}, proc { |p| p.start_command = "run" })
      expect(proxy.attributes).to eq(start_command: "run")
    end

    it "reads attributes that have been set" do
      proxy = described_class.new("web", {}, proc { self.start_command = "run" })
      expect(proxy.start_command).to eq("run")
    end

    it "reads an attribute that has not been set as nil" do
      expect(described_class.new("web", {}, proc {}).start_command).to be_nil
    end

    it "reads the attributes the app set" do
      expect(described_class.new("web", {uid: "user"}, proc {}).uid).to eq("user")
    end

    it "sets an attribute to false or nil" do
      proxy = described_class.new("web", {}, proc do |p|
        p.auto_start = false
        p.pid_file = nil
      end)
      expect(proxy.attributes).to eq(auto_start: false, pid_file: nil)
    end

    it "sets the group" do
      proxy = described_class.new("web", {}, proc { |p| p.group = "workers" })
      expect(proxy.attributes).to eq(group: "workers")
    end

    it "sets every configurable attribute, but the two that monitor_children sets" do
      (Bluepill::Process::CONFIGURABLE_ATTRIBUTES - %i[monitor_children child_process_factory]).each do |attribute|
        proxy = described_class.new("web", {}, proc { |p| p.public_send(:"#{attribute}=", 1) })
        expect([proxy.attributes, proxy.public_send(attribute)]).to eq([{attribute => 1}, 1])
      end
    end

    it "names the attributes a config can set" do
      expect(described_class.attribute_names).to eq(
        Bluepill::Process::CONFIGURABLE_ATTRIBUTES - %i[monitor_children child_process_factory] + [:group]
      )
    end

    it "rejects child_process_factory, which monitor_children sets" do
      expect { described_class.new("web", {}, proc { |p| p.child_process_factory = 1 }) }
        .to raise_error(Bluepill::ConfigError, /Unknown attribute 'child_process_factory' for process 'web'/)
    end

    it "rejects an unknown attribute, and suggests the closest one" do
      expect { described_class.new("web", {}, proc { |p| p.start_comand = "run" }) }.to raise_error(
        Bluepill::ConfigError, "Unknown attribute 'start_comand' for process 'web'. Did you mean 'start_command'?"
      )
    end

    it "suggests the setter for a bang method, which bluepill 0.2 took" do
      expect { described_class.new("web", {}, proc { daemonize! }) }.to raise_error(
        Bluepill::ConfigError, "Unknown attribute 'daemonize!' for process 'web'. Did you mean 'daemonize'?"
      )
    end

    it "rejects a value given as an argument, which bluepill 0.2 took" do
      expect { described_class.new("web", {}, proc { start_command "run" }) }.to raise_error(ArgumentError)
    end

    it "suggests the group" do
      expect { described_class.new("web", {}, proc { |p| p.grop = "workers" }) }.to raise_error(
        Bluepill::ConfigError, "Unknown attribute 'grop' for process 'web'. Did you mean 'group'?"
      )
    end

    it "replaces an attribute the app already set" do
      proxy = described_class.new("web", {working_dir: "/app"}, proc { |p| p.working_dir = "/web" })
      expect(proxy.attributes).to eq(working_dir: "/web")
    end

    it "reads no pid for a process that isn't a child" do
      expect(described_class.new("web", {}, proc {}).actual_pid).to be_nil
    end

    it "reads a child process's pid" do
      value = nil
      described_class.new("<child(pid:5)>", {}, proc { value = actual_pid }, actual_pid: 5)
      expect(value).to eq(5)
    end

    it "doesn't set a child process's pid" do
      expect { described_class.new("<child(pid:5)>", {}, proc { |p| p.actual_pid = 6 }, actual_pid: 5) }
        .to raise_error(Bluepill::ConfigError, /Unknown attribute 'actual_pid'/)
    end
  end

  describe "#checks" do
    before { allow(Bluepill::Process).to receive(:new) }

    it "gives the process each check with its options, in order" do
      described_class.new("web", {}, proc do
        checks :cpu_usage, every: 10, below: 5
        checks :always_true
      end).to_process
      expect(Bluepill::Process).to have_received(:new).with("web", [[:cpu_usage, {every: 10, below: 5}], [:always_true, {}]], actual_pid: nil)
    end

    it "keeps two checks of a kind" do
      described_class.new("web", {}, proc do
        checks :http, url: "http://localhost/a"
        checks :http, url: "http://localhost/b"
      end).to_process
      expect(Bluepill::Process).to have_received(:new).with("web", [[:http, {url: "http://localhost/a"}], [:http, {url: "http://localhost/b"}]], actual_pid: nil)
    end

    it "returns nothing" do
      value = :unset
      described_class.new("web", {}, proc { value = checks(:always_true) })
      expect(value).to be_nil
    end
  end

  describe "#monitor_children" do
    it "keeps the child process block out of the attributes" do
      child_block = proc {}
      proxy = described_class.new("web", {}, proc { |p| p.monitor_children(&child_block) })
      expect([proxy.child_process_block, proxy.attributes]).to eq([child_block, {}])
    end

    it "returns the block" do
      child_block = proc {}
      value = nil
      described_class.new("web", {}, proc { |p| value = p.monitor_children(&child_block) })
      expect(value).to be(child_block)
    end

    it "requires a block" do
      expect { described_class.new("web", {}, proc { monitor_children }) }.to raise_error(
        Bluepill::ConfigError, "monitor_children for process 'web' needs a block that configures the children"
      )
    end
  end

  describe "#to_process" do
    let(:proxy) do
      described_class.new("web", {}, proc do
        self.start_command = "run"
        checks :always_true, every: 10
      end)
    end

    it "builds a process from its watches and attributes" do
      expect(proxy.to_process).to be_a(Bluepill::Process).and have_attributes(
        name: "web", start_command: "run", watches: have_attributes(count: 1)
      )
    end

    it "leaves the group out of the process's attributes" do
      allow(Bluepill::Process).to receive(:new)
      described_class.new("web", {uid: "user"}, proc { self.group = "servers" }).to_process
      expect(Bluepill::Process).to have_received(:new).with("web", [], actual_pid: nil, uid: "user")
    end

    it "gives the process a child's pid, and more options" do
      allow(Bluepill::Process).to receive(:new)
      logger = instance_double(Bluepill::Logger)
      described_class.new("child", {uid: "user"}, proc {}, actual_pid: 5).to_process(logger:)
      expect(Bluepill::Process).to have_received(:new).with("child", [], actual_pid: 5, uid: "user", logger:)
    end

    it "gives the process a watch for each of two checks of a kind" do
      proxy = described_class.new("web", {}, proc do
        checks :always_true, every: 10
        checks :always_true, every: 20
      end)
      expect(proxy.to_process.watches.collect(&:name)).to eq(%i[always_true always_true])
    end
  end
end
