# frozen_string_literal: true

describe Bluepill do
  describe ".setup_bundler" do
    before do
      allow(described_class).to receive(:require)
    end

    it "sets up Bundler when the Gemfile exists" do
      described_class.setup_bundler(__FILE__)
      expect(described_class).to have_received(:require).with("bundler/setup")
    end

    it "does nothing when the Gemfile is missing" do
      described_class.setup_bundler("/nonexistent/Gemfile")
      expect(described_class).not_to have_received(:require)
    end

    it "does nothing without a Gemfile" do
      described_class.setup_bundler(nil)
      expect(described_class).not_to have_received(:require)
    end

    context "without an argument" do
      around do |example|
        gemfile = ENV.fetch("BUNDLE_GEMFILE", nil)
        example.run
        ENV["BUNDLE_GEMFILE"] = gemfile
      end

      it "uses BUNDLE_GEMFILE" do
        ENV["BUNDLE_GEMFILE"] = __FILE__
        described_class.setup_bundler
        expect(described_class).to have_received(:require).with("bundler/setup")
      end

      it "does nothing when BUNDLE_GEMFILE is unset" do
        ENV.delete("BUNDLE_GEMFILE")
        described_class.setup_bundler
        expect(described_class).not_to have_received(:require)
      end
    end
  end

  describe ".application" do
    let(:app) { instance_double(Bluepill::Application, load: nil) }
    let(:options) { {foreground: true} }

    before do
      allow(Bluepill::Application).to receive(:new).with("app_name", **options).and_return(app)
    end

    it "evaluates a block without arguments in the context of the app proxy" do
      context = nil
      described_class.application(:app_name, **options) { context = self }
      expect(context).to be_a(Bluepill::AppProxy).and have_attributes(app: app)
    end

    it "loads the app after a block without arguments" do
      described_class.application(:app_name, **options) { nil }
      expect(app).to have_received(:load)
    end

    it "yields the app proxy to a block with one argument" do
      yielded = nil
      described_class.application(:app_name, **options) { |a| yielded = a }
      expect(yielded).to be_a(Bluepill::AppProxy).and have_attributes(app: app)
    end

    it "loads the app after a block with one argument" do
      described_class.application(:app_name, **options) { |_app| nil }
      expect(app).to have_received(:load)
    end

    it "prints a config error and exits with status 6" do
      expect { described_class.application(:app_name, **options) { raise Bluepill::ConfigError, "Config Error: bad" } }
        .to raise_error(an_instance_of(SystemExit).and(having_attributes(status: 6)))
        .and output("Config Error: bad\n").to_stderr
    end

    it "prints another Bluepill::Error and exits with its status" do
      allow(app).to receive(:load).and_raise(Bluepill::StartupError, "Failed to start bluepill")
      expect { described_class.application(:app_name, **options) { nil } }
        .to raise_error(an_instance_of(SystemExit).and(having_attributes(status: 5)))
        .and output("Failed to start bluepill\n").to_stderr
    end

    it "lets other errors through" do
      expect { described_class.application(:app_name, **options) { raise ArgumentError, "bad" } }.to raise_error(ArgumentError, "bad")
    end

    it "defaults to no options" do
      allow(Bluepill::Application).to receive(:new).with("app_name").and_return(app)
      described_class.application(:app_name) { |_app| } # an app with no processes
      expect(app).to have_received(:load)
    end
  end
end
