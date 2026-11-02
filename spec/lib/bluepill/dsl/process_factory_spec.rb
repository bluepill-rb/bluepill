# frozen_string_literal: true

describe Bluepill::ProcessFactory do
  let(:registry) { Bluepill::ProcessFactory::Registry.new }
  # The application's logger, whose prefixed loggers are memoized, so a
  # spec can find the one a process got
  let(:logger) { Bluepill::Logger.new(logger: instance_double(Bluepill::Logger::LoggerAdapter)) }

  # Silence the warning for processes without a known pid. The output
  # matcher swaps $stderr, so specs can still check what is written.
  before { allow($stderr).to receive(:puts) }

  def create(name, block, attributes = {})
    process, = Bluepill::ProcessFactory.new(attributes, block, registry).create_process(name, "/pids", logger:)
    process
  end

  # Expect the block to fail with a config error with the message
  def expect_config_error(message, &block)
    expect(&block).to raise_error(Bluepill::ConfigError, message.is_a?(String) ? message.chomp : message)
  end

  describe "#create_process" do
    it "creates a process" do
      process = create("web", proc { self.start_command = "run" })
      expect(process).to be_a(Bluepill::Process).and have_attributes(name: "web", start_command: "run")
    end

    it "assigns a default pid file from the process name" do
      process = create("web server", proc { self.start_command = "run" })
      expect(process.pid_file).to eq("/pids/web_server.pid")
    end

    it "replaces every unsafe character in the default pid file" do
      process = create("my web/server", proc { self.start_command = "run" })
      expect(process.pid_file).to eq("/pids/my_web_server.pid")
    end

    it "assigns a default pid file from the group and process name" do
      process = create("web", proc { self.start_command = "run" }, group: "my group")
      expect(process.pid_file).to eq("/pids/my_group_web.pid")
    end

    it "keeps an explicit pid file" do
      process = create("web", proc { self.start_command = "run" }, pid_file: "/var/web.pid")
      expect(process.pid_file).to eq("/var/web.pid")
    end

    it "returns the group that the block sets" do
      factory = described_class.new({}, proc do
        self.start_command = "run"
        self.group = "servers"
      end, registry)
      expect(factory.create_process("web", "/pids", logger:)).to match([be_a(Bluepill::Process), "servers"])
    end

    it "returns no group when the process has none" do
      factory = described_class.new({}, proc { self.start_command = "run" }, registry)
      expect(factory.create_process("web", "/pids", logger:)).to match([be_a(Bluepill::Process), nil])
    end

    it "gives the process the app's logger, prefixed with its group's name and its own" do
      process = create("web", proc do
        self.start_command = "run"
        self.group = :servers
      end)
      expect(process.logger).to be(logger.prefix_with("servers").prefix_with("web"))
    end

    it "gives a process without a group the app's logger, prefixed with its name" do
      process = create("web", proc { self.start_command = "run" })
      expect(process.logger).to be(logger.prefix_with(nil).prefix_with("web"))
    end

    it "leaves the factory's attributes as they were" do
      attributes = {uid: "user"}
      block = proc { |p| p.monitor_children { self.stop_command = "halt" } && p.start_command = "run" }
      described_class.new(attributes, block, registry).create_process("web", "/pids", logger:)
      expect(attributes).to eq(uid: "user")
    end

    it "checks each process against a registry of its own by default" do
      described_class.new({}, proc { self.start_command = "run" }).create_process("web", "/pids", logger:)
      expect { described_class.new({}, proc { self.start_command = "run" }).create_process("web", "/pids", logger:) }.not_to raise_error
    end

    context "when monitoring children" do
      let(:process) do
        create("web", proc do |p|
          p.start_command = "run"
          p.monitor_children { self.stop_command = "halt" }
        end)
      end

      it "monitors the children" do
        expect(process.monitor_children).to be true
      end

      it "creates a child process factory" do
        expect(process.child_process_factory).to be_a(Bluepill::ProcessFactory::ChildFactory)
      end

      it "gives the children the process's attributes" do
        allow(Bluepill::ProcessFactory::ChildFactory).to receive(:new)
        create("web", proc { (self.uid = "deploy") && monitor_children { self.stop_command = "halt" } }, start_command: "run")
        expect(Bluepill::ProcessFactory::ChildFactory).to have_received(:new).with("web", hash_including(uid: "deploy"), Proc)
      end

      it "checks the children's config when the process's loads" do
        expect_config_error("Config Error: You must specify a stop_command for the children of 'web'") do
          create("web", proc { (self.start_command = "run") && monitor_children { self.uid = "user" } })
        end
      end

      it "creates children from the child process block" do
        allow(::Process).to receive(:kill).with(0, 123).and_return(1)
        child = process.child_process_factory.create_child_process("child", 123, instance_double(Bluepill::Logger))
        expect(child).to have_attributes(stop_command: "halt", state: :up)
      end
    end

    it "does not monitor the children otherwise" do
      process = create("web", proc { self.start_command = "run" })
      expect([process.monitor_children, process.child_process_factory]).to eq([false, nil])
    end

    it "lets the app give each process a pid file" do
      expect(create("web", proc { self.start_command = "run" }, pid_file: "/var/web.pid").pid_file).to eq("/var/web.pid")
    end

    it "gives a block that reads the pid file the default one" do
      pid_file = nil
      create("web", proc { (self.start_command = "run") && pid_file = self.pid_file })
      expect(pid_file).to eq("/pids/web.pid")
    end

    describe "validation" do
      it "rejects duplicate process names in a group" do
        create("web", proc { self.start_command = "run" }, group: "servers")
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create("web", proc { self.start_command = "run" }, group: "servers")
        end
      end

      it "rejects duplicate process names without a group" do
        create("web", proc { self.start_command = "run" })
        expect_config_error("Config Error: You have two entries for the process name 'web'\n") do
          create("web", proc { self.start_command = "run" }, pid_file: "/other.pid")
        end
      end

      it "names the group that the process block sets" do
        block = proc { (self.start_command = "run") && self.group = "servers" }
        create("web", block)
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create("web", block, pid_file: "/other.pid")
        end
      end

      it "accepts the same process name in different groups" do
        create("web", proc { self.start_command = "run" }, group: "a")
        expect { create("web", proc { self.start_command = "run" }, group: "b") }.not_to raise_error
      end

      it "accepts process names that only match when joined with a colon" do
        create("b:c", proc { self.start_command = "run" }, group: "a")
        expect { create("c", proc { self.start_command = "run" }, group: "a:b", pid_file: "/pids/c.pid") }.not_to raise_error
      end

      it "treats Symbol and String group and process names alike" do
        create(:web, proc { self.start_command = "run" }, group: :servers)
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create("web", proc { self.start_command = "run" }, group: "servers", pid_file: "/other.pid")
        end
      end

      it "tells a group without a name from no group" do
        create("web", proc { self.start_command = "run" })
        expect { create("web", proc { self.start_command = "run" }, group: "", pid_file: "/other.pid") }.not_to raise_error
      end

      it "requires a start command" do
        expect_config_error("Config Error: You must specify a start_command for 'web'\n") do
          create("web", proc {})
        end
      end

      it "rejects duplicate pid files" do
        create("web", proc { self.start_command = "run" }, pid_file: "/shared.pid")
        expect_config_error("Config Error: You have two entries with the pid file: /shared.pid\n") do
          create("worker", proc { self.start_command = "run" }, pid_file: " /shared.pid ")
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
        expect { create("web", proc { self.start_command = "run" }) }.to output(warning).to_stderr
      end

      it "warns about a process with daemonize set to false" do
        expect { create("web", proc { self.start_command = "run" }, daemonize: false) }.to output(warning).to_stderr
      end

      it "warns about a process with a nil pid command" do
        expect { create("web", proc { self.start_command = "run" }, pid_command: nil) }.to output(warning).to_stderr
      end

      it "warns about a process that sets the default pid file itself" do
        block = proc do
          self.start_command = "run"
          self.pid_file = "/pids/web.pid"
        end
        expect { create("web", block) }.to output(warning).to_stderr
      end

      it "does not warn about a daemonized process" do
        expect { create("web", proc { self.start_command = "run" }, daemonize: true) }.not_to output.to_stderr
      end

      it "does not warn about a process with a pid command" do
        expect { create("web", proc { self.start_command = "run" }, pid_command: "pgrep web") }.not_to output.to_stderr
      end

      it "does not warn about a process with its own pid file" do
        block = proc do
          self.start_command = "run"
          self.pid_file = "/var/web.pid"
        end
        expect { create("web", block) }.not_to output.to_stderr
      end

      it "does not warn about a pid file set before the default is assigned" do
        expect { create("web", proc { self.start_command = "run" }, pid_file: "/var/web.pid") }.not_to output.to_stderr
      end
    end

    describe "on_start_timeout" do
      def create_with(event, name = "web") = create(name, proc { (self.start_command = "run") && self.on_start_timeout = event })

      it "accepts each event of the state machine" do
        events = %i[start stop unmonitor restart]
        expect(events.collect { |event| create_with(event, event.to_s).on_start_timeout }).to eq(events)
      end

      it "defaults to start" do
        expect(create("web", proc { self.start_command = "run" }).on_start_timeout).to be(:start)
      end

      it "rejects an event the state machine doesn't have" do
        expect_config_error("Config Error: on_start_timeout for 'web' must be one of :start, :stop, :unmonitor, :restart, not :tick") do
          create_with(:tick)
        end
      end

      it "rejects a String" do
        expect_config_error(/must be one of .*, not "unmonitor"\z/) { create_with("unmonitor") }
      end

      it "rejects nil" do
        expect_config_error(/must be one of .*, not nil\z/) { create_with(nil) }
      end
    end

    describe "stop_signals" do
      def create_with_signals(signals, grace_time)
        create("web", proc do
          self.start_command = "run"
          self.stop_signals = signals
          self.stop_grace_time = grace_time unless grace_time.nil?
        end)
      end

      it "accepts valid stop signals" do
        process = create_with_signals([:quit, 5, :term], 10)
        expect(process.stop_signals.to_a).to eq([:quit, 5, :term])
      end

      it "parses the stop signals once" do
        allow(Bluepill::Process::StopSignals).to receive(:new).and_call_original
        create_with_signals([:quit, 5, :term], 10)
        expect(Bluepill::Process::StopSignals).to have_received(:new).once
      end

      it "accepts a single stop signal" do
        process = create_with_signals([:term], 10)
        expect(process.stop_signals.to_a).to eq([:term])
      end

      it "accepts Active Support durations as delays" do
        process = create_with_signals([:quit, 5.seconds, :term], 10)
        expect(process.stop_signals.to_a).to eq([:quit, 5, :term])
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
        expect(process.stop_signals.to_a).to eq([:quit, 9, :term])
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
end
