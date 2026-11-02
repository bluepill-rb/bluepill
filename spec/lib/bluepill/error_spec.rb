# frozen_string_literal: true

require "tmpdir"

# Each error class's group names it for mutant, which otherwise picks the
# specs for a subject by the top-level group's description
describe Bluepill::Error do
  it "is a StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end

  it "makes the bluepill command exit with 1" do
    expect(described_class.new.exit_status).to eq(1)
  end

  {
    Bluepill::ConfigError => 6,
    Bluepill::StartupError => 5,
    Bluepill::PreviousDaemonError => 4,
    Bluepill::AlreadyRunningError => 7,
    Bluepill::ConnectionError => 1,
    Bluepill::VersionMismatchError => 1,
    Bluepill::UnknownCommandError => 1
  }.each do |error_class, status|
    describe error_class, mutant_expression: "#{error_class.name}*" do
      it "is a Bluepill::Error that makes the bluepill command exit with #{status}" do
        expect([described_class.superclass.name, described_class.new.exit_status]).to eq(["Bluepill::Error", status])
      end
    end
  end

  describe Bluepill::DaemonError, mutant_expression: "Bluepill::DaemonError*" do
    let(:daemon_error) { RuntimeError.new("boom").tap { |error| error.set_backtrace(["a.rb:1", "b.rb:2"]) } }
    let(:error) { described_class.new(daemon_error) }

    it "is a Bluepill::Error that makes the bluepill command exit with 8" do
      expect([described_class.superclass.name, error.exit_status]).to eq(["Bluepill::Error", 8])
    end

    it "keeps the daemon's error" do
      expect(error.daemon_error).to be(daemon_error)
    end

    it "says what the daemon raised, with its backtrace" do
      expect(error.message).to eq("Received error from server:\n#{daemon_error.inspect}\na.rb:1\nb.rb:2")
    end

    it "leaves out a backtrace the daemon's error doesn't have" do
      error = described_class.new(RuntimeError.new("boom"))
      expect(error.message).to eq("Received error from server:\n#<RuntimeError: boom>")
    end
  end

  describe Bluepill::ConfigError, mutant_expression: "Bluepill::ConfigError*" do
    it "keeps its message" do
      expect(described_class.new("Config Error: bad").message).to eq("Config Error: bad")
    end

    describe "#location" do
      let(:dir) { Dir.mktmpdir }

      after { FileUtils.remove_entry(dir) }

      # Write a file in the temporary directory, and return its path
      def write(name, code)
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, code)
        path
      end

      # Load a pill file with code, and return the location of the
      # ConfigError it raises
      def location_of(code)
        load(write("app.pill.rb", code))
      rescue described_class => e
        e.location
      end

      def raise_config_error = "raise Bluepill::ConfigError, 'bad'\n"

      # Raise a ConfigError with the backtrace of a NameError on line 2
      def reraise_name_error
        <<~RUBY
          begin
            undefined_method_here
          rescue NameError => e
            raise Bluepill::ConfigError, 'bad', e.backtrace
          end
        RUBY
      end

      it "is the line of the pill file that raised it" do
        expect(location_of("x = 1\n#{raise_config_error}")).to eq("#{dir}/app.pill.rb:2")
      end

      it "is the line of the error it replaced, when it was raised with that error's backtrace" do
        expect(location_of(reraise_name_error)).to eq("#{dir}/app.pill.rb:2")
      end

      it "skips eval'd code, which isn't in a file" do
        expect(location_of("instance_eval(#{raise_config_error.inspect})")).to eq("#{dir}/app.pill.rb:1")
      end

      # Put a stand-in for bluepill's lib in the temporary directory, with a
      # file that raises
      def stand_in_lib
        stub_const("Bluepill::ConfigError::LIBRARY_DIR", "#{File.realpath(dir)}/lib/")
        write("lib/bluepill/dsl.rb", raise_config_error)
      end

      it "skips the frames in bluepill's own code" do
        stand_in_lib
        expect(location_of("x = 1\nload #{"#{dir}/lib/bluepill/dsl.rb".inspect}")).to eq("#{dir}/app.pill.rb:2")
      end

      it "skips them when bluepill's lib is loaded through a symlink" do
        stand_in_lib
        File.symlink(File.join(dir, "lib"), File.join(dir, "linked"))
        expect(location_of("load #{"#{dir}/linked/bluepill/dsl.rb".inspect}")).to eq("#{dir}/app.pill.rb:1")
      end

      it "skips a frame whose file is gone" do
        gone = write("gone.rb", "File.delete(__FILE__)\n#{raise_config_error}")
        expect(location_of("load #{gone.inspect}")).to eq("#{dir}/app.pill.rb:1")
      end

      it "is a line of a file that the pill file loads" do
        helper = write("helper.rb", "x = 1\n#{raise_config_error}")
        expect(location_of("load #{helper.inspect}")).to eq("#{dir}/helper.rb:2")
      end

      it "is nil for an error that wasn't raised" do
        expect(described_class.new("bad").location).to be_nil
      end
    end

    describe "LIBRARY_DIR" do
      it "is the real path of bluepill's lib directory" do
        expect(described_class::LIBRARY_DIR).to eq("#{File.realpath(File.join(BLUEPILL_ROOT, "lib"))}/")
      end
    end
  end
end
