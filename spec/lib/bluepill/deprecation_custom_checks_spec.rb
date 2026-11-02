# frozen_string_literal: true

describe Bluepill::Deprecation do
  let(:logger) { instance_double(Bluepill::Logger) }

  # A check class named Bluepill::ProcessConditions::SpecCheck, made from
  # base with the block
  def check_class(base = Bluepill::ProcessConditions::ProcessCondition, &block)
    stub_const("Bluepill::ProcessConditions::SpecCheck", Class.new(base, &block))
  end

  # A check class that defines run and check?, and its own initialize
  def complete_check(&initialize)
    check_class do
      define_method(:initialize, &initialize) if initialize
      define_method(:run) { |_pid, _include_children| 1 }
      define_method(:check?) { |_value| true }
    end
  end

  # A trigger class named Bluepill::Triggers::SpecTrigger, made with the
  # block
  def trigger_class(&block)
    # Trigger.inherited can't register a class without a name
    allow(Bluepill::Trigger).to receive(:inherited)
    stub_const("Bluepill::Triggers::SpecTrigger", Class.new(Bluepill::Trigger, &block))
  end

  def positional_message(kind, klass)
    "DEPRECATION: bluepill 0.3.0 passes a #{kind}'s options as keyword arguments, " \
      "so the initialize of #{klass}, which takes them as a Hash, fails when it calls super. " \
      "Name the options it needs, as in def initialize(path:, below:, **options), " \
      "and call super(**options), which 0.2.9 takes too.\n"
  end

  describe ".check_condition_class" do
    it "warns about a custom initialize that takes an options Hash" do
      klass = complete_check { |options = {}| super(options) }
      expect { described_class.check_condition_class(klass) }.to output(positional_message("check", klass)).to_stderr
    end

    it "warns about a custom initialize that takes a required options Hash" do
      klass = complete_check { |options| super(options) }
      expect { described_class.check_condition_class(klass) }.to output(positional_message("check", klass)).to_stderr
    end

    it "warns about a custom initialize that takes its arguments as a list" do
      klass = complete_check { |*args| super(*args) }
      expect { described_class.check_condition_class(klass) }.to output(positional_message("check", klass)).to_stderr
    end

    it "says nothing about a custom initialize that takes keywords" do
      klass = complete_check { |below:, **options| super(**options) && below }
      expect { described_class.check_condition_class(klass) }.not_to output.to_stderr
    end

    it "says nothing about a check that keeps bluepill's initialize" do
      expect { described_class.check_condition_class(complete_check) }.not_to output.to_stderr
    end

    it "says nothing about bluepill's own checks" do
      checks = %i[always_true cpu_usage file_time http mem_usage running_time zombie_process].collect { |name| Bluepill::ProcessConditions[name] }
      expect { checks.each { |klass| described_class.check_condition_class(klass) } }.not_to output.to_stderr
    end

    it "warns about a check that defines check instead of check?" do
      klass = check_class { define_method(:check) { |_value| true } }
      klass.define_method(:run) { |_pid, _include_children| 1 }
      message = "DEPRECATION: bluepill 0.3.0 calls only check?, so #{klass}, which defines check, fails the config. " \
                "Rename its check method check?, which 0.2.9 calls too.\n"
      expect { described_class.check_condition_class(klass) }.to output(message).to_stderr
    end

    it "says nothing about a check that defines check? and check" do
      klass = complete_check
      klass.define_method(:check) { |_value| true }
      expect { described_class.check_condition_class(klass) }.not_to output.to_stderr
    end

    def methods_message(klass, missing)
      "DEPRECATION: bluepill 0.3.0 fails the config when a check doesn't define run and check?, " \
        "and #{klass} doesn't define #{missing}. Define it, or remove the check.\n"
    end

    it "warns about a check that defines neither run nor check?" do
      klass = check_class
      expect { described_class.check_condition_class(klass) }.to output(methods_message(klass, "run or check?")).to_stderr
    end

    it "warns about a check that doesn't define run" do
      klass = check_class { define_method(:check?) { |_value| true } }
      expect { described_class.check_condition_class(klass) }.to output(methods_message(klass, "run")).to_stderr
    end

    it "warns about a check that doesn't define check?" do
      klass = check_class { define_method(:run) { |_pid, _include_children| 1 } }
      expect { described_class.check_condition_class(klass) }.to output(methods_message(klass, "check?")).to_stderr
    end

    it "warns about a check that subclasses MemUsage" do
      klass = check_class(Bluepill::ProcessConditions::MemUsage)
      message = "DEPRECATION: bluepill 0.3.0 gives a check that subclasses MemUsage the memory usage in bytes, " \
                "where 0.2 gives kilobytes, so the run, check? and format_value of #{klass} " \
                "get values 1024 times larger. Change them when you upgrade.\n"
      expect { described_class.check_condition_class(klass) }.to output(message).to_stderr
    end
  end

  describe ".check_trigger_class" do
    it "warns about a custom initialize that takes an options Hash" do
      klass = trigger_class do
        define_method(:initialize) { |process, options = {}| super(process, options) }
        define_method(:notify) { |_transition| nil }
      end
      expect { described_class.check_trigger_class(klass) }.to output(positional_message("trigger", klass)).to_stderr
    end

    it "warns about a custom initialize that takes the rest of its arguments as a list" do
      klass = trigger_class do
        define_method(:initialize) { |process, *args| super(process, *args) }
        define_method(:notify) { |_transition| nil }
      end
      expect { described_class.check_trigger_class(klass) }.to output(positional_message("trigger", klass)).to_stderr
    end

    it "says nothing about a custom initialize that takes keywords" do
      klass = trigger_class do
        define_method(:initialize) { |process, within: 1, **options| super(process, **options) && within }
        define_method(:notify) { |_transition| nil }
      end
      expect { described_class.check_trigger_class(klass) }.not_to output.to_stderr
    end

    it "says nothing about bluepill's own trigger" do
      expect { described_class.check_trigger_class(Bluepill::Triggers::Flapping) }.not_to output.to_stderr
    end

    it "warns about a trigger that doesn't define notify" do
      klass = trigger_class
      expect { described_class.check_trigger_class(klass) }.to output(
        "DEPRECATION: bluepill 0.3.0 fails the config when a trigger doesn't define notify, " \
        "and #{klass} doesn't. Define it, or remove the trigger.\n"
      ).to_stderr
    end
  end

  describe ".check_logger" do
    let(:check) { complete_check { |_options = {}| nil }.new }

    it "warns about a check that has no logger after its initialize" do
      expect { described_class.check_logger(check, logger) }.to output(
        "DEPRECATION: bluepill 0.3.0 gives #{check.class} its logger only through super, " \
        "which its initialize doesn't call, so it has no logger. Call super(**options) in its initialize.\n"
      ).to_stderr
    end

    it "says nothing about a check that kept its logger" do
      expect { described_class.check_logger(complete_check.new(logger: logger), logger) }.not_to output.to_stderr
    end

    it "says nothing when there was no logger to give" do
      expect { described_class.check_logger(check, nil) }.not_to output.to_stderr
    end
  end

  describe ".check_logger_writer" do
    let(:check) { complete_check.new }

    it "warns about a logger= called from outside bluepill" do
      location = caller_locations(0, 1).first
      expect { described_class.check_logger_writer(check, location) }.to output(
        "DEPRECATION: bluepill 0.3.0 removes the logger= of checks and triggers, which #{location} " \
        "calls on #{check.class}. Let it get its logger from super(**options) in its initialize.\n"
      ).to_stderr
    end

    it "warns when a check sets its own logger" do
      expect { check.logger = logger }.to output(/removes the logger= of checks and triggers, which #{__FILE__}/o).to_stderr
    end

    it "warns when a trigger's logger is set from outside bluepill" do
      trigger = Bluepill::Trigger.new(nil, logger: logger)
      expect { trigger.logger = logger }.to output(/on Bluepill::Trigger\./).to_stderr
    end

    it "says nothing about bluepill's own code" do
      location = instance_double(Thread::Backtrace::Location, path: File.join(BLUEPILL_ROOT, "lib", "bluepill", "condition_watch.rb"))
      expect { described_class.check_logger_writer(check, location) }.not_to output.to_stderr
    end

    it "says nothing about bluepill's own code at a relative path" do
      location = instance_double(Thread::Backtrace::Location, path: "lib/bluepill/condition_watch.rb")
      Dir.chdir(BLUEPILL_ROOT) do
        expect { described_class.check_logger_writer(check, location) }.not_to output.to_stderr
      end
    end

    it "says nothing without a location" do
      expect { described_class.check_logger_writer(check, nil) }.not_to output.to_stderr
    end

    it "says nothing when the watch sets the logger" do
      watch = Bluepill::ConditionWatch.new(:always_true, every: 10)
      expect { watch.logger = logger }.not_to output.to_stderr
    end
  end

  describe ".check_trigger_event" do
    let(:trigger) { Bluepill::Trigger.new(nil, logger: logger) }

    it "warns about a String event" do
      expect { described_class.check_trigger_event(trigger, "start") }.to output(
        "DEPRECATION: bluepill 0.3.0 takes a process's events only as Symbols, so Bluepill::Trigger " \
        "fails when it dispatches \"start\". Dispatch :start, which 0.2.9 takes too.\n"
      ).to_stderr
    end

    it "says nothing about a Symbol" do
      expect { described_class.check_trigger_event(trigger, :start) }.not_to output.to_stderr
    end

    it "is checked when a trigger dispatches" do
      process = instance_double(Bluepill::Process, dispatch!: true)
      expect { Bluepill::Trigger.new(process, logger: logger).dispatch!("stop") }.to output(/dispatches "stop"/).to_stderr
    end
  end

  describe ".custom?" do
    it "is true for a method outside bluepill" do
      expect(described_class.custom?(complete_check.instance_method(:run))).to be(true)
    end

    it "is false for a method of bluepill's" do
      expect(described_class.custom?(Bluepill::Trigger.instance_method(:notify))).to be(false)
    end

    it "is false for bluepill's method at a relative path" do
      method = instance_double(UnboundMethod, source_location: ["lib/bluepill/trigger.rb", 1])
      expect(Dir.chdir(BLUEPILL_ROOT) { described_class.custom?(method) }).to be(false)
    end

    it "is false for a method of Ruby's own, which has no source" do
      expect(described_class.custom?(BasicObject.instance_method(:initialize))).to be(false)
    end
  end
end
