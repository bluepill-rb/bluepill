# frozen_string_literal: true

describe Bluepill do
  describe ".application" do
    let(:app) { instance_double(Bluepill::Application, load: nil) }

    before { allow(Bluepill::Application).to receive(:new).and_return(app) }

    it "checks the Ruby that runs it" do
      described_class.application("app") { nil }
      expect(Bluepill::Deprecation).to have_received(:check_ruby)
    end

    it "loads the application" do
      described_class.application("app") { nil }
      expect(app).to have_received(:load)
    end
  end
end
