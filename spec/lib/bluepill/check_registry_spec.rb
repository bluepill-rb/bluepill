# frozen_string_literal: true

describe Bluepill::CheckRegistry do
  # Forget the checks an example defines
  around do |example|
    entries = described_class.instance_variable_get(:@entries).dup
    example.run
    described_class.instance_variable_set(:@entries, entries)
  end

  # A check that defines what a check must, in a module of the config's own
  def custom_check(name, superclass = Bluepill::ProcessConditions::ProcessCondition)
    stub_const(name, Class.new(superclass) do
      define_method(:run) { |_pid, _include_children| 1 }
      define_method(:check?) { |_value| true }
    end)
  end

  describe ".fetch" do
    it "finds the built-in checks and triggers by their underscored names" do
      checks = %i[cpu_usage mem_usage http flapping].collect { |name| described_class.fetch(name) }
      conditions = Bluepill::ProcessConditions
      expect(checks).to eq([conditions::CpuUsage, conditions::MemUsage, conditions::Http, Bluepill::Triggers::Flapping])
    end

    it "takes a name as a String" do
      expect(described_class.fetch("zombie_process")).to equal(Bluepill::ProcessConditions::ZombieProcess)
    end

    it "finds a check defined outside ProcessConditions" do
      klass = custom_check("MyApp::Checks::LogSize")
      expect(described_class.fetch(:log_size)).to equal(klass)
    end

    it "finds a check that builds on another check" do
      klass = custom_check("MyApp::BigMemory", Bluepill::ProcessConditions::MemUsage)
      expect(described_class.fetch(:big_memory)).to equal(klass)
    end

    it "finds the check defined last when two have the same name" do
      custom_check("First::LogSize")
      klass = custom_check("Second::LogSize")
      expect(described_class.fetch(:log_size)).to equal(klass)
    end

    it "skips a class without a name" do
      Class.new(Bluepill::ProcessConditions::AlwaysTrue)
      expect(described_class.fetch(:always_true)).to equal(Bluepill::ProcessConditions::AlwaysTrue)
    end

    it "matches the whole name, not a part of it" do
      custom_check("MyApp::MemUsageTotal")
      expect(described_class.fetch(:mem_usage)).to equal(Bluepill::ProcessConditions::MemUsage)
    end

    it "suggests a check for a misspelled name" do
      expect { described_class.fetch(:mem_usag) }
        .to raise_error(Bluepill::ConfigError, "Unknown check 'mem_usag'. Did you mean 'mem_usage'?")
    end

    it "suggests the closest check when several are close" do
      custom_check("MyApp::MemUsages")
      expect { described_class.fetch(:mem_usage_) }
        .to raise_error(Bluepill::ConfigError, "Unknown check 'mem_usage_'. Did you mean 'mem_usage'?")
    end

    it "suggests nothing for a name like no check's" do
      expect { described_class.fetch(:xyzzy) }.to raise_error(Bluepill::ConfigError, "Unknown check 'xyzzy'")
    end

    it "has no check named below, which a config uses as an option" do
      expect { described_class.fetch(:below) }.to raise_error(Bluepill::ConfigError, /\AUnknown check 'below'/)
    end

    it "requires a check to define run and check?" do
      stub_const("MyApp::Empty", Class.new(Bluepill::ProcessConditions::ProcessCondition))
      expect { described_class.fetch(:empty) }
        .to raise_error(Bluepill::ConfigError, "MyApp::Empty, the class of check 'empty', must define run and check?")
    end

    it "requires a check to define what its base doesn't" do
      stub_const("MyApp::Limit", Class.new(Bluepill::ProcessConditions::BelowThreshold))
      expect { described_class.fetch(:limit) }
        .to raise_error(Bluepill::ConfigError, "MyApp::Limit, the class of check 'limit', must define run")
    end

    it "takes a check? from the class a check builds on" do
      check = Class.new(Bluepill::ProcessConditions::BelowThreshold) { define_method(:run) { |_pid, _children| 1 } }
      klass = stub_const("MyApp::Limit", check)
      expect(described_class.fetch(:limit)).to equal(klass)
    end
  end

  describe ".names" do
    it "leaves out a check that doesn't define what it must" do
      stub_const("MyApp::Empty", Class.new(Bluepill::ProcessConditions::ProcessCondition))
      expect(described_class.names).not_to include("empty")
    end

    it "lists only names, without a nil for a class without one" do
      Class.new(Bluepill::ProcessConditions::AlwaysTrue)
      expect(described_class.names).to all(be_a(String))
    end

    it "includes a custom check" do
      custom_check("MyApp::LogSize")
      expect(described_class.names).to include("log_size")
    end
  end

  describe ".check_name" do
    {
      "Flapping" => "flapping",
      "Bluepill::ProcessConditions::MemUsage" => "mem_usage",
      "A::B::HTTPCheck" => "http_check"
    }.each do |name, check_name|
      it "names #{name} #{check_name}" do
        expect(described_class.check_name(instance_double(Class, name:))).to eq(check_name)
      end
    end

    it "has no name for an anonymous class" do
      expect(described_class.check_name(Class.new)).to be_nil
    end
  end
end
