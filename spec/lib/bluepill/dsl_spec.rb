describe Bluepill do
  describe '.application' do
    let(:app) { instance_double(Bluepill::Application, load: nil) }
    let(:options) { {foreground: true} }

    before do
      allow(Bluepill::Application).to receive(:new).with('app_name', options).and_return(app)
    end

    it 'evaluates a block without arguments in the context of the app proxy' do
      context = nil
      Bluepill.application(:app_name, options) { context = self }
      expect(context).to be_a(Bluepill::AppProxy)
      expect(app).to have_received(:load)
    end

    it 'yields the app proxy to a block with one argument' do
      yielded = nil
      Bluepill.application(:app_name, options) { |a| yielded = a }
      expect(yielded).to be_a(Bluepill::AppProxy)
      expect(yielded.app).to eq(app)
      expect(app).to have_received(:load)
    end

    it 'warns on a Ruby that bluepill 0.2 does not run on, once the app has its logger' do
      expect(Bluepill::Application).to receive(:new).ordered.and_return(app)
      expect(Bluepill).to receive(:warn_unsupported_ruby).with(no_args).ordered
      Bluepill.application(:app_name, options) {}
    end

    it 'defaults to no options' do
      expect(Bluepill::Application).to receive(:new).with('app_name', {}).and_return(app)
      Bluepill.application(:app_name) {}
      expect(app).to have_received(:load)
    end
  end

  describe '.warn_unsupported_ruby' do
    def warning(ruby)
      'DEPRECATION: bluepill 0.2.0 needs Ruby 2.0 or JRuby 9.0, and later 0.2 releases need Ruby 2.7 or JRuby 9.4, ' \
        "so it won't run on #{ruby}. Stay on bluepill 0.1 until you upgrade Ruby.\n"
    end

    it 'warns on Ruby 1.9.3' do
      expect { Bluepill.warn_unsupported_ruby('1.9.3', nil) }.to output(warning('Ruby 1.9.3')).to_stderr
    end

    it 'warns on JRuby 1.7, in its Ruby 1.9 mode or its Ruby 2.0 mode' do
      expect { Bluepill.warn_unsupported_ruby('1.9.3', '1.7.27') }.to output(warning('Ruby 1.9.3 (JRuby 1.7.27)')).to_stderr
      expect { Bluepill.warn_unsupported_ruby('2.0.0', '1.7.27') }.to output(warning('Ruby 2.0.0 (JRuby 1.7.27)')).to_stderr
    end

    it 'does not warn on Ruby 2.0, or JRuby 9.0 and newer' do
      expect { Bluepill.warn_unsupported_ruby('2.0.0', nil) }.not_to output.to_stderr
      expect { Bluepill.warn_unsupported_ruby('2.1.10', nil) }.not_to output.to_stderr
      expect { Bluepill.warn_unsupported_ruby('2.2.3', '9.0.5.0') }.not_to output.to_stderr
      expect { Bluepill.warn_unsupported_ruby('2.3.3', '9.1.17.0') }.not_to output.to_stderr
      expect { Bluepill.warn_unsupported_ruby('3.4.1', '10.0.0.0') }.not_to output.to_stderr
      expect { Bluepill.warn_unsupported_ruby('10.0.0', nil) }.not_to output.to_stderr
    end

    it 'checks the Ruby it runs on by default' do
      stub_const('RUBY_VERSION', '1.9.3')
      hide_const('JRUBY_VERSION')
      expect { Bluepill.warn_unsupported_ruby }.to output(warning('Ruby 1.9.3')).to_stderr
    end

    it 'checks the JRuby it runs on by default' do
      stub_const('RUBY_VERSION', '2.0.0')
      stub_const('JRUBY_VERSION', '1.7.27')
      expect { Bluepill.warn_unsupported_ruby }.to output(warning('Ruby 2.0.0 (JRuby 1.7.27)')).to_stderr
    end
  end
end
