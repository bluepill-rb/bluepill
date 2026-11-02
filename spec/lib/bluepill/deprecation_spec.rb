# frozen_string_literal: true

describe Bluepill::Deprecation do
  let(:logger) { instance_double(Bluepill::Logger, warning: nil) }

  describe ".warn" do
    it "writes the message to stderr" do
      expect { described_class.warn(:key, "it changes") }.to output("DEPRECATION: it changes\n").to_stderr
    end

    it "warns once for each key" do
      expect do
        2.times { described_class.warn(:key, "it changes") }
        described_class.warn(:other, "so does this")
      end.to output("DEPRECATION: it changes\nDEPRECATION: so does this\n").to_stderr
    end

    it "logs the message at warning when there's a logger" do
      allow($stderr).to receive(:puts)
      described_class.logger = logger
      described_class.warn(:key, "it changes")
      expect(logger).to have_received(:warning).with("DEPRECATION: it changes")
    end
  end

  describe ".logger" do
    it "is the logger it was given" do
      described_class.logger = logger
      expect(described_class.logger).to be(logger)
    end
  end

  describe ".reset!" do
    before do
      allow($stderr).to receive(:puts)
      described_class.logger = logger
      described_class.warn(:key, "it changes")
      described_class.reset!
    end

    it "forgets the warnings given" do
      expect { described_class.warn(:key, "it changes") }.to output("DEPRECATION: it changes\n").to_stderr
    end

    it "forgets the logger" do
      expect(described_class.logger).to be_nil
    end
  end

  describe ".check_ruby" do
    before { allow(described_class).to receive(:check_ruby).and_call_original }

    it "warns on Ruby 2.7" do
      expect { described_class.check_ruby("2.7.8") }.to output(
        "DEPRECATION: bluepill 0.3.0 needs Ruby 3.0 or newer, or JRuby 9.4 or newer, and this is Ruby 2.7.8. " \
        "Upgrade Ruby before you upgrade bluepill, or stay on 0.2.9.\n"
      ).to_stderr
    end

    it "says nothing on Ruby 3.0" do
      expect { described_class.check_ruby("3.0.0") }.not_to output.to_stderr
    end

    it "compares versions as versions, not as Strings" do
      expect { described_class.check_ruby("10.0.0") }.not_to output.to_stderr
    end

    it "checks the Ruby that runs it by default" do
      allow(described_class).to receive(:warn)
      described_class.check_ruby
      expect(described_class).to have_received(:warn).exactly((RUBY_VERSION < "3") ? 1 : 0).times
    end
  end
end
