# frozen_string_literal: true

describe Bluepill::ProcessFactory do
  let(:registry) { Bluepill::ProcessFactory::Registry.new }

  # Silence the warning for processes without a known pid. The output
  # matcher swaps $stderr, so specs can still check what is written.
  before { allow($stderr).to receive(:puts) }

  def create(name, block, attributes = {})
    process, = Bluepill::ProcessFactory.new(attributes, block, registry).create_process(name, "/pids")
    process
  end

  def expect_config_error(message, &block)
    expect do
      expect(&block).to raise_error(SystemExit) { |e| expect(e.status).to eq(6) }
    end.to output(message).to_stderr
  end

  describe "#create_process" do
    it "creates a process" do
      process = create("web", proc { start_command "run" })
      expect(process).to be_a(Bluepill::Process).and have_attributes(name: "web", start_command: "run")
    end

    it "assigns a default pid file from the process name" do
      process = create("web server", proc { start_command "run" })
      expect(process.pid_file).to eq("/pids/web_server.pid")
    end

    it "replaces every unsafe character in the default pid file" do
      process = create("my web/server", proc { start_command "run" })
      expect(process.pid_file).to eq("/pids/my_web_server.pid")
    end

    it "assigns a default pid file from the group and process name" do
      process = create("web", proc { start_command "run" }, group: "my group")
      expect(process.pid_file).to eq("/pids/my_group_web.pid")
    end

    it "keeps an explicit pid file" do
      process = create("web", proc { start_command "run" }, pid_file: "/var/web.pid")
      expect(process.pid_file).to eq("/var/web.pid")
    end

    it "returns the group that the block sets" do
      factory = described_class.new({}, proc do
        start_command "run"
        group "servers"
      end, registry)
      expect(factory.create_process("web", "/pids")).to match([be_a(Bluepill::Process), "servers"])
    end

    it "returns no group when the process has none" do
      factory = described_class.new({}, proc { start_command "run" }, registry)
      expect(factory.create_process("web", "/pids")).to match([be_a(Bluepill::Process), nil])
    end

    it "leaves the factory's attributes as they were" do
      attributes = {uid: "user"}
      block = proc { |p| p.start_command("run") && p.monitor_children { stop_command "halt" } }
      described_class.new(attributes, block, registry).create_process("web", "/pids")
      expect(attributes).to eq(uid: "user")
    end

    it "checks each process against a registry of its own by default" do
      described_class.new({}, proc { start_command "run" }).create_process("web", "/pids")
      expect { described_class.new({}, proc { start_command "run" }).create_process("web", "/pids") }.not_to raise_error
    end

    it "exposes its attributes" do
      factory = described_class.new({uid: "user"}, proc {})
      expect(factory.attributes).to eq(uid: "user")
    end

    context "when monitoring children" do
      let(:process) do
        create("web", proc do |p|
          p.start_command "run"
          p.monitor_children { stop_command "halt" }
        end)
      end

      it "monitors the children" do
        expect(process.monitor_children).to be true
      end

      it "creates a child process factory" do
        expect(process.child_process_factory).to be_a(described_class)
      end

      it "keeps the child process block out of the child attributes" do
        expect(process.child_process_factory.attributes).not_to have_key(:child_process_block)
      end

      it "creates children from the child process block" do
        allow(::Process).to receive(:kill).with(0, 123).and_return(1)
        child = process.child_process_factory.create_child_process("child", 123, instance_double(Bluepill::Logger))
        expect(child).to have_attributes(stop_command: "halt", state: :up)
      end
    end

    it "does not create a child process factory when monitor_children is false" do
      process = create("web", proc do |p|
        p.start_command "run"
        p.monitor_children = false
      end)
      expect(process.child_process_factory).to be_nil
    end

    it "does not create a child process factory otherwise" do
      process = create("web", proc { start_command "run" })
      expect(process.child_process_factory).to be_nil
    end

    describe "validation" do
      it "rejects duplicate process names in a group" do
        create("web", proc { start_command "run" }, group: "servers")
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create("web", proc { start_command "run" }, group: "servers")
        end
      end

      it "rejects duplicate process names without a group" do
        create("web", proc { start_command "run" })
        expect_config_error("Config Error: You have two entries for the process name 'web'\n") do
          create("web", proc { start_command "run" }, pid_file: "/other.pid")
        end
      end

      it "names the group that the process block sets" do
        block = proc { start_command("run") && group("servers") }
        create("web", block)
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create("web", block, pid_file: "/other.pid")
        end
      end

      it "accepts the same process name in different groups" do
        create("web", proc { start_command "run" }, group: "a")
        expect { create("web", proc { start_command "run" }, group: "b") }.not_to raise_error
      end

      it "accepts process names that only match when joined with a colon" do
        create("b:c", proc { start_command "run" }, group: "a")
        expect { create("c", proc { start_command "run" }, group: "a:b", pid_file: "/pids/c.pid") }.not_to raise_error
      end

      it "treats Symbol and String group and process names alike" do
        create(:web, proc { start_command "run" }, group: :servers)
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create("web", proc { start_command "run" }, group: "servers", pid_file: "/other.pid")
        end
      end

      it "tells a group without a name from no group" do
        create("web", proc { start_command "run" })
        expect { create("web", proc { start_command "run" }, group: "", pid_file: "/other.pid") }.not_to raise_error
      end

      it "requires a start command" do
        expect_config_error("Config Error: You must specify a start_command for 'web'\n") do
          create("web", proc {})
        end
      end

      it "rejects duplicate pid files" do
        create("web", proc { start_command "run" }, pid_file: "/shared.pid")
        expect_config_error("Config Error: You have two entries with the pid file: /shared.pid\n") do
          create("worker", proc { start_command "run" }, pid_file: " /shared.pid ")
        end
      end
    end

    context "without a known pid" do
      let(:warning) do
        "Config Warning: 'web' sets no daemonize, pid_file or pid_command, " \
          "so bluepill cannot find its pid unless start_command writes it to /pids/web.pid. " \
          "Set daemonize = true if start_command runs in the foreground.\n"
      end

      it "warns about a process that is not daemonized and uses the default pid file" do
        expect { create("web", proc { start_command "run" }) }.to output(warning).to_stderr
      end

      it "warns about a process with daemonize set to false" do
        expect { create("web", proc { start_command "run" }, daemonize: false) }.to output(warning).to_stderr
      end

      it "warns about a process with a nil pid command" do
        expect { create("web", proc { start_command "run" }, pid_command: nil) }.to output(warning).to_stderr
      end

      it "warns about a process that sets the default pid file itself" do
        block = proc do
          start_command "run"
          pid_file "/pids/web.pid"
        end
        expect { create("web", block) }.to output(warning).to_stderr
      end

      it "does not warn about a daemonized process" do
        expect { create("web", proc { start_command "run" }, daemonize: true) }.not_to output.to_stderr
      end

      it "does not warn about a process with a pid command" do
        expect { create("web", proc { start_command "run" }, pid_command: "pgrep web") }.not_to output.to_stderr
      end

      it "does not warn about a process with its own pid file" do
        block = proc do
          start_command "run"
          pid_file "/var/web.pid"
        end
        expect { create("web", block) }.not_to output.to_stderr
      end

      it "does not warn about a pid file set before the default is assigned" do
        expect { create("web", proc { start_command "run" }, pid_file: "/var/web.pid") }.not_to output.to_stderr
      end
    end

    describe "stop_signals" do
      def create_with_signals(signals, grace_time)
        create("web", proc do
          start_command "run"
          stop_signals signals
          stop_grace_time grace_time unless grace_time.nil?
        end)
      end

      it "accepts valid stop signals" do
        process = create_with_signals([:quit, 5, :term], 10)
        expect(process.stop_signals).to eq([:quit, 5, :term])
      end

      it "accepts a single stop signal" do
        process = create_with_signals([:term], 10)
        expect(process.stop_signals).to eq([:term])
      end

      it "accepts Active Support durations as delays" do
        process = create_with_signals([:quit, 5.seconds, :term], 10)
        expect(process.stop_signals).to eq([:quit, 5, :term])
      end

      # An Integer that isn't an instance of Integer. Every Integer is one
      # since Ruby 2.4, so this keeps is_a? from passing as instance_of?.
      it "accepts any kind of Integer as a delay" do
        delay = instance_double(Integer, is_a?: true)
        expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
          create_with_signals([:quit, delay, :term], nil)
        end
      end

      it "accepts a stop_grace_time just above the sum of the delays" do
        process = create_with_signals([:quit, 9, :term], 10)
        expect(process.stop_signals).to eq([:quit, 9, :term])
      end

      it "rejects a stop_grace_time below the sum of the delays" do
        expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
          create_with_signals([:quit, 10, :term], 5)
        end
      end

      it "requires signals to be symbols" do
        expect_config_error(/Expected a symbol \(signal\) at position 2 instead of 'term'/) do
          create_with_signals([:quit, 5, "term"], 10)
        end
      end

      it "requires delays to be numbers" do
        expect_config_error(/Expected a number \(delay\) at position 1 instead of 'five'/) do
          create_with_signals([:quit, "five", :term], 10)
        end
      end

      it "requires an odd number of elements" do
        expect_config_error("Config Error: Invalid stop_signals!  Expected an odd number of elements.\n") do
          create_with_signals([:quit, 5], 10)
        end
      end

      it "requires a stop_grace_time" do
        expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
          create_with_signals([:quit, 5, :term], nil)
        end
      end

      it "requires stop_grace_time to exceed the sum of the delays" do
        expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
          create_with_signals([:quit, 5, :term, 5, :kill], 10)
        end
      end
    end
  end

  describe "#create_child_process" do
    let(:logger) { instance_double(Bluepill::Logger) }
    let(:attributes) { {start_grace_time: 1, stop_grace_time: 2, restart_grace_time: 5, uid: "user", gid: "staff", supplementary_groups: ["rvm"], working_dir: "/srv"} }

    before { allow(::Process).to receive(:kill).with(0, 123).and_return(1) }

    def create_child(attributes, block)
      described_class.new(attributes, block).create_child_process("child", 123, logger)
    end

    it "creates a child process with the grace times, user and groups of its parent" do
      expect(create_child(attributes, proc { stop_command "halt" })).to be_a(Bluepill::Process).and have_attributes(
        state: :up, name: "child", actual_pid: 123, logger: logger, stop_command: "halt",
        start_grace_time: 1, stop_grace_time: 2, restart_grace_time: 5,
        uid: "user", gid: "staff", supplementary_groups: ["rvm"], working_dir: nil
      )
    end

    it "gives a child the default grace times when its parent sets none" do
      child = create_child({}, proc { stop_command "halt" })
      expect([child.start_grace_time, child.stop_grace_time, child.restart_grace_time]).to eq([3, 3, 3])
    end

    it "requires a stop command" do
      message = "Config Error: Invalid child process monitor for child\nYou must specify a stop command to monitor child processes.\n"
      expect_config_error(message) do
        create_child(attributes, proc {})
      end
    end
  end
end
