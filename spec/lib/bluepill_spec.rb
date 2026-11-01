describe Bluepill do
  describe '.setup_bundler' do
    before do
      allow(Bluepill).to receive(:require)
    end

    it 'sets up Bundler when the Gemfile exists' do
      Bluepill.setup_bundler(__FILE__)
      expect(Bluepill).to have_received(:require).with('bundler/setup')
    end

    it 'does nothing when the Gemfile is missing' do
      Bluepill.setup_bundler('/nonexistent/Gemfile')
      expect(Bluepill).not_to have_received(:require)
    end

    it 'does nothing without a Gemfile' do
      Bluepill.setup_bundler(nil)
      expect(Bluepill).not_to have_received(:require)
    end

    context 'without an argument' do
      around do |example|
        gemfile = ENV['BUNDLE_GEMFILE']
        example.run
        ENV['BUNDLE_GEMFILE'] = gemfile
      end

      it 'uses BUNDLE_GEMFILE' do
        ENV['BUNDLE_GEMFILE'] = __FILE__
        Bluepill.setup_bundler
        expect(Bluepill).to have_received(:require).with('bundler/setup')
      end

      it 'does nothing when BUNDLE_GEMFILE is unset' do
        ENV.delete('BUNDLE_GEMFILE')
        Bluepill.setup_bundler
        expect(Bluepill).not_to have_received(:require)
      end
    end
  end
end
