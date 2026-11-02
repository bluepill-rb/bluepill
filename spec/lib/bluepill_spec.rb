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
      allow(Bluepill::Application).to receive(:new).with("app_name", options).and_return(app)
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

    it "checks the Ruby that runs it" do
      described_class.application(:app_name, **options) { nil }
      expect(Bluepill::Deprecation).to have_received(:check_ruby)
    end

    it "warns about options passed as a Hash, without **" do
      expect { described_class.application(:app_name, options, **{}) { nil } }.to output(
        "DEPRECATION: bluepill 0.3.0 takes the options of Bluepill.application \"app_name\" only as keyword arguments, " \
        "so options kept in a Hash fail unless they're passed with **. Write Bluepill.application \"app_name\", **options, which 0.2 takes too.\n"
      ).to_stderr
    end

    it "warns about an option that 0.3.0 rejects" do
      allow(Bluepill::Application).to receive(:new).with("app_name", {log_flie: "a.log"}).and_return(app)
      expect { described_class.application(:app_name, log_flie: "a.log") { nil } }.to output(
        "DEPRECATION: bluepill 0.3.0 rejects the application option log_flie:, which 0.2 ignores. Remove it, or fix its name.\n"
      ).to_stderr
    end

    it "says nothing about the options that 0.3.0 takes" do
      all = {foreground: true, log_file: "a.log", log_level: :info, base_dir: "/tmp", kill_timeout: 5}
      allow(Bluepill::Application).to receive(:new).and_return(app)
      expect { described_class.application(:app_name, **all) { nil } }.not_to output.to_stderr
    end

    it "raises for options passed as a Hash and as keywords, as before" do
      expect { described_class.application(:app_name, {foreground: true}, log_file: "a.log") { nil } }.to raise_error(ArgumentError)
    end

    it "takes options passed as a Hash" do
      allow($stderr).to receive(:puts)
      described_class.application(:app_name, options, **{}) { nil }
      expect(app).to have_received(:load)
    end

    it "defaults to no options" do
      allow(Bluepill::Application).to receive(:new).with("app_name", {}).and_return(app)
      described_class.application(:app_name) { |_app| } # an app with no processes
      expect(app).to have_received(:load)
    end
  end
end
