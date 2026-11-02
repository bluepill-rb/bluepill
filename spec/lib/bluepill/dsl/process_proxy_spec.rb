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
      attributes = {uid: "user"}
      proxy = described_class.new("web", attributes, proc {})
      expect(proxy).to have_attributes(name: "web", attributes: equal(attributes), watches: {})
    end
  end

  describe "attribute DSL" do
    it "sets attributes with a setter" do
      proxy = described_class.new("web", {}, proc { |p| p.start_command = "run" })
      expect(proxy.attributes).to eq(start_command: "run")
    end

    it "sets attributes with a single argument" do
      proxy = described_class.new("web", {}, proc { stop_command "halt" })
      expect(proxy.attributes).to eq(stop_command: "halt")
    end

    it "sets attributes to true with a bang method" do
      proxy = described_class.new("web", {}, proc { daemonize! })
      expect(proxy.attributes).to eq(daemonize: true)
    end

    it "responds to setters, bang methods and attributes that have been set" do
      proxy = described_class.new("web", {uid: "user"}, proc {})
      expect(proxy).to respond_to(:start_command=, :daemonize!, :uid)
    end

    it "does not respond to attributes that have not been set" do
      proxy = described_class.new("web", {uid: "user"}, proc {})
      expect(proxy).not_to respond_to(:gid)
    end

    it "reads attributes that have been set" do
      proxy = described_class.new("web", {}, proc { start_command "run" })
      expect(proxy.start_command).to eq("run")
    end

    it "raises NameError for unknown attributes without arguments" do
      expect { described_class.new("web", {}, proc { start_command }) }.to raise_error(NameError)
    end

    it "raises NoMethodError when called with several arguments" do
      expect { described_class.new("web", {start_command: "a"}, proc { start_command "a", "b" }) }.to raise_error(NoMethodError, /undefined method/)
    end

    it "sets an attribute to false or nil" do
      proxy = described_class.new("web", {}, proc do |p|
        p.auto_start = false
        p.pid_file nil
      end)
      expect(proxy.attributes).to eq(auto_start: false, pid_file: nil)
    end

    it "sets the group" do
      proxy = described_class.new("web", {}, proc { |p| p.group = "workers" })
      expect(proxy.attributes).to eq(group: "workers")
    end

    it "sets every configurable attribute" do
      Bluepill::Process::CONFIGURABLE_ATTRIBUTES.each do |attribute|
        proxy = described_class.new("web", {}, proc { |p| p.public_send("#{attribute}=", 1) })
        expect(proxy.attributes).to eq(attribute => 1)
      end
    end

    it "rejects an unknown attribute set with a setter, and suggests the closest one" do
      expect { described_class.new("web", {}, proc { |p| p.start_comand = "run" }) }.to raise_error(
        NoMethodError, "Unknown attribute 'start_comand' for process 'web'. Did you mean 'start_command'?"
      )
    end

    it "names the unknown attribute in the error" do
      expect { described_class.new("web", {}, proc { |p| p.start_comand = "run" }) }.to raise_error(
        a_kind_of(NoMethodError).and(having_attributes(name: :start_comand))
      )
    end

    it "rejects an unknown attribute set with an argument" do
      expect { described_class.new("web", {}, proc { stop_comand "halt" }) }.to raise_error(
        NoMethodError, "Unknown attribute 'stop_comand' for process 'web'. Did you mean 'stop_command'?"
      )
    end

    it "rejects an unknown attribute set with a bang method" do
      expect { described_class.new("web", {}, proc { daemonise! }) }.to raise_error(
        NoMethodError, "Unknown attribute 'daemonise' for process 'web'. Did you mean 'daemonize'?"
      )
    end

    it "rejects an unknown attribute that is read" do
      expect { described_class.new("web", {}, proc { pidfile }) }.to raise_error(
        NoMethodError, "Unknown attribute 'pidfile' for process 'web'. Did you mean 'pid_file'?"
      )
    end

    it "suggests nothing for an attribute unlike any other" do
      expect { described_class.new("worker", {}, proc { |p| p.frobnicate = 1 }) }.to raise_error(
        NoMethodError, "Unknown attribute 'frobnicate' for process 'worker'"
      )
    end

    it "replaces an attribute the app already set" do
      proxy = described_class.new("web", {working_dir: "/app"}, proc { |p| p.working_dir = "/web" })
      expect(proxy.attributes).to eq(working_dir: "/web")
    end

    it "reads an attribute that bluepill sets, such as a child process pid" do
      value = nil
      described_class.new("<child(pid:5)>", {actual_pid: 5}, proc { value = actual_pid })
      expect(value).to eq(5)
    end

    it "suggests the closest attribute by its name" do
      proxy = described_class.new("web", {}, proc {})
      expect(proxy.send(:suggest, :start_comand)).to eq("start_command")
    end

    it "suggests an attribute at most a third of the name away" do
      proxy = described_class.new("web", {}, proc {})
      suggestions = %i[auto_srt uidx gids ui].collect { |name| proxy.send(:suggest, name) }
      expect(suggestions).to eq(["auto_start", "uid", "gid", nil])
    end

    it "suggests the first in order among attributes as close as each other" do
      proxy = described_class.new("web", {}, proc {})
      expect(proxy.send(:suggest, :xid)).to eq("gid")
    end

    it "leaves a bang method with an argument to NoMethodError" do
      expect { described_class.new("web", {}, proc { daemonize! true }) }.to raise_error(NoMethodError, /undefined method/)
    end

    it "leaves a setter without an argument to NoMethodError" do
      expect { described_class.new("web", {}, proc { |p| p.__send__(:start_command=) }) }.to raise_error(NoMethodError, /undefined method/)
    end

    it "responds to unknown attributes no more than it accepts them" do
      proxy = described_class.new("web", {}, proc {})
      expect(proxy).not_to respond_to(:start_comand=, :daemonise!, :pidfile)
    end

    it "responds to the group setter" do
      proxy = described_class.new("web", {}, proc {})
      expect(proxy).to respond_to(:group=)
    end
  end

  describe "#checks" do
    it "records a watch with its options" do
      proxy = described_class.new("web", {}, proc do
        checks :cpu_usage, every: 10, below: 5
        checks :always_true
      end)
      expect(proxy.watches).to eq(cpu_usage: {every: 10, below: 5}, always_true: {})
    end
  end

  describe "#monitor_children" do
    it "stores the child process block" do
      child_block = proc {}
      proxy = described_class.new("web", {}, proc { |p| p.monitor_children(&child_block) })
      expect(proxy.attributes).to eq(monitor_children: true, child_process_block: child_block)
    end
  end

  describe "#to_process" do
    let(:proxy) do
      described_class.new("web", {}, proc do
        start_command "run"
        checks :always_true, every: 10
      end)
    end

    it "builds a process from its watches and attributes" do
      expect(proxy.to_process).to be_a(Bluepill::Process).and have_attributes(
        name: "web", start_command: "run", watches: have_attributes(count: 1)
      )
    end
  end
end
