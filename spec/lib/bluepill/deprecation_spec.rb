describe Bluepill::Deprecation do
  let(:logger) { instance_double(Bluepill::Logger, warning: nil) }

  describe '.warn' do
    it 'writes the message to stderr, after DEPRECATION' do
      expect { Bluepill::Deprecation.warn(:key, 'bluepill 0.2.0 changes it.') }.
        to output("DEPRECATION: bluepill 0.2.0 changes it.\n").to_stderr
    end

    it 'logs the message at warning when there is a logger' do
      Bluepill::Deprecation.logger = logger
      expect { Bluepill::Deprecation.warn(:key, 'bluepill 0.2.0 changes it.') }.to output.to_stderr
      expect(logger).to have_received(:warning).with('DEPRECATION: bluepill 0.2.0 changes it.').once
    end

    it 'warns once for each key' do
      Bluepill::Deprecation.logger = logger
      expect do
        expect(Bluepill::Deprecation.warn(:key, 'first')).to be(true)
        expect(Bluepill::Deprecation.warn(:key, 'again')).to be(false)
        expect(Bluepill::Deprecation.warn(:other, 'other')).to be(true)
      end.to output("DEPRECATION: first\nDEPRECATION: other\n").to_stderr
      expect(logger).to have_received(:warning).twice
    end
  end

  describe '.first?' do
    it 'is true only the first time for each key' do
      expect(Bluepill::Deprecation.first?(:key)).to be(true)
      expect(Bluepill::Deprecation.first?(:key)).to be(false)
      expect(Bluepill::Deprecation.first?('key')).to be(true)
      expect(Bluepill::Deprecation.first?(:key)).to be(false)
    end

    it 'remembers the key under a lock, since watches and triggers run in threads' do
      mutex = Bluepill::Deprecation.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).once.and_call_original
      expect(Bluepill::Deprecation.first?(:key)).to be(true)
    end
  end

  describe '.reset!' do
    it 'forgets the warnings under the lock' do
      mutex = Bluepill::Deprecation.instance_variable_get(:@mutex)
      expect(mutex).to receive(:synchronize).once.and_call_original
      Bluepill::Deprecation.reset!
    end

    it 'forgets the warnings given, and the logger' do
      Bluepill::Deprecation.logger = logger
      expect { Bluepill::Deprecation.warn(:key, 'first') }.to output.to_stderr
      Bluepill::Deprecation.reset!
      expect(Bluepill::Deprecation.logger).to be_nil
      expect { Bluepill::Deprecation.warn(:key, 'again') }.to output("DEPRECATION: again\n").to_stderr
      expect(logger).to have_received(:warning).once
    end
  end
end
