describe Bluepill do
  describe '.setup_bundler' do
    before do
      allow(described_class).to receive(:require)
    end

    it 'sets up Bundler when the Gemfile exists' do
      described_class.setup_bundler(__FILE__)
      expect(described_class).to have_received(:require).with('bundler/setup')
    end

    it 'does nothing when the Gemfile is missing' do
      described_class.setup_bundler('/nonexistent/Gemfile')
      expect(described_class).not_to have_received(:require)
    end

    it 'does nothing without a Gemfile' do
      described_class.setup_bundler(nil)
      expect(described_class).not_to have_received(:require)
    end

    context 'without an argument' do
      around do |example|
        gemfile = ENV.fetch('BUNDLE_GEMFILE', nil)
        example.run
        ENV['BUNDLE_GEMFILE'] = gemfile
      end

      it 'uses BUNDLE_GEMFILE' do
        ENV['BUNDLE_GEMFILE'] = __FILE__
        described_class.setup_bundler
        expect(described_class).to have_received(:require).with('bundler/setup')
      end

      it 'does nothing when BUNDLE_GEMFILE is unset' do
        ENV.delete('BUNDLE_GEMFILE')
        described_class.setup_bundler
        expect(described_class).not_to have_received(:require)
      end
    end
  end
end
