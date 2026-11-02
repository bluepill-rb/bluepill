require 'syslog'
require 'tmpdir'

describe Bluepill::Logger do
  around do |example|
    Dir.mktmpdir do |dir|
      @log_file = File.join(dir, 'bluepill.log')
      example.run
    end
  end

  describe '#initialize' do
    it 'logs to syslog without a log file' do
      syslog = double('syslog')
      allow(Syslog).to receive(:opened?).and_return(false)
      expect(Syslog).not_to receive(:close)
      expect(Syslog).to receive(:open).with('bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(syslog)
      expect(syslog).to receive(:info).with('hello')
      described_class.new.info('hello')
    end

    it 'closes an already opened syslog and uses the given identity' do
      allow(Syslog).to receive(:opened?).and_return(true)
      expect(Syslog).to receive(:close)
      expect(Syslog).to receive(:open).with('myapp', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(double('syslog'))
      described_class.new(identity: 'myapp')
    end

    it 'explains how to fix a missing syslog library' do
      hide_const('Syslog')
      allow_any_instance_of(described_class).to receive(:require).with('syslog').and_raise(LoadError)
      expect { described_class.new }.to raise_error(LoadError, /add gem 'syslog' to your Gemfile or set log_file/)
    end

    it 'does not load syslog when logging to a log file' do
      expect_any_instance_of(described_class).not_to receive(:require)
      described_class.new(log_file: @log_file)
    end

    it 'logs to a log file' do
      described_class.new(log_file: @log_file).err('something failed')
      expect(File.read(@log_file)).to include('ERROR -- : something failed')
    end

    it 'logs to syslog when log_file is nil' do
      allow(Syslog).to receive(:opened?).and_return(false)
      expect(Syslog).to receive(:open).with('bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(double('syslog'))
      described_class.new(log_file: nil)
    end

    it 'prefixes messages with the given prefix' do
      inner = double('inner')
      expect(inner).to receive(:info).with('[app] message')
      parent = described_class.new(logger: inner)
      described_class.new(logger: parent, prefix: 'app').info('message')
    end

    it 'writes to stdout if requested' do
      inner = double('inner', info: nil)
      expect($stdout).to receive(:puts).with('[info]: message')
      expect($stdout).to receive(:flush)
      described_class.new(logger: inner, stdout: true).info('message')
    end

    it 'does not write to stdout when stdout is false' do
      inner = double('inner', info: nil)
      expect($stdout).not_to receive(:puts)
      described_class.new(logger: inner, stdout: false).info('message')
    end

    it 'starts without prefixed loggers' do
      expect(described_class.new(logger: double('inner')).prefix_with('app')).to be_a(described_class)
    end

    it 'uses a given logger' do
      inner = double('inner')
      expect(inner).to receive(:warning).with('careful')
      described_class.new(logger: inner).warning('careful')
    end

    context 'with a log_level' do
      let(:inner) { double('inner', emerg: nil, err: nil, warning: nil, notice: nil, info: nil, debug: nil) }

      it 'logs everything by default' do
        described_class.new(logger: inner).debug('details')
        expect(inner).to have_received(:debug).with('details')
      end

      it 'logs messages at or above the level' do
        logger = described_class.new(logger: inner, log_level: :warning)
        logger.warning('careful')
        logger.err('failed')
        logger.emerg('down')
        expect(inner).to have_received(:warning).with('careful')
        expect(inner).to have_received(:err).with('failed')
        expect(inner).to have_received(:emerg).with('down')
      end

      it 'drops messages below the level without formatting them' do
        message = double('message')
        expect(message).not_to receive(:to_s)
        logger = described_class.new(logger: inner, log_level: :warning, stdout: true)
        expect($stdout).not_to receive(:puts)
        logger.notice(message)
        logger.info(message)
        logger.debug(message)
        expect(inner).not_to have_received(:notice)
        expect(inner).not_to have_received(:info)
        expect(inner).not_to have_received(:debug)
      end

      it 'logs only the most severe messages at emerg' do
        logger = described_class.new(logger: inner, log_level: :emerg)
        logger.err('failed')
        logger.emerg('down')
        expect(inner).not_to have_received(:err)
        expect(inner).to have_received(:emerg).with('down')
      end

      it 'takes the level as a string' do
        described_class.new(logger: inner, log_level: 'notice').info('hello')
        expect(inner).not_to have_received(:info)
      end

      it 'drops messages below the level in a log file' do
        logger = described_class.new(log_file: @log_file, log_level: :err)
        logger.warning('careful')
        logger.err('failed')
        expect(File.read(@log_file)).not_to include('careful')
        expect(File.read(@log_file)).to include('ERROR -- : failed')
      end

      it 'keeps the stricter of a prefixed logger level and its parent' do
        inner = double('inner', warning: nil, info: nil, debug: nil)
        parent = described_class.new(logger: inner, log_level: :info)
        described_class.new(logger: parent, prefix: 'app', log_level: :debug).debug('details')
        described_class.new(logger: parent, prefix: 'app', log_level: :warning).info('hello')
        described_class.new(logger: parent, prefix: 'app', log_level: :warning).warning('careful')
        expect(inner).not_to have_received(:debug)
        expect(inner).not_to have_received(:info)
        expect(inner).to have_received(:warning).with('[app] careful')
      end

      it 'echoes prefixed messages to stdout from the parent' do
        inner = double('inner', info: nil)
        expect($stdout).to receive(:puts).with('[info]: [app] hello')
        expect($stdout).to receive(:flush)
        described_class.new(logger: inner, stdout: true).prefix_with('app').info('hello')
      end

      it 'adds more prefixes after its own' do
        inner = double('inner', info: nil)
        described_class.new(logger: inner).prefix_with('app').info('hello', ['web', nil])
        expect(inner).to have_received(:info).with('[app:web] hello')
      end

      it 'adds every parent prefix, the outermost first' do
        inner = double('inner', info: nil)
        app = described_class.new(logger: described_class.new(logger: inner), prefix: 'app')
        described_class.new(logger: app, prefix: 'web').info('hello')
        expect(inner).to have_received(:info).with('[app:web] hello')
      end

      it 'does not echo prefixed messages unless the parent does' do
        inner = double('inner', info: nil)
        expect($stdout).not_to receive(:puts)
        described_class.new(logger: described_class.new(logger: inner), prefix: 'app').info('hello')
      end

      it 'rejects an unknown level' do
        expect { described_class.new(logger: inner, log_level: :verbose) }.to raise_error(
          ArgumentError, 'Unknown log_level :verbose. Use one of: emerg, alert, crit, err, warning, notice, info, debug'
        )
      end
    end
  end

  describe 'log methods' do
    it 'also writes to stdout if requested' do
      inner = double('inner', debug: nil)
      expect($stdout).to receive(:puts).with('[debug]: [a:b] message')
      expect($stdout).to receive(:flush)
      described_class.new(logger: inner, stdout: true).debug('message', ['a', nil, 'b'])
      expect(inner).to have_received(:debug).with('[a:b] message')
    end
  end

  describe '#prefix_with' do
    let(:inner) { double('inner') }
    let(:logger) { described_class.new(logger: inner) }

    it 'prefixes messages' do
      expect(inner).to receive(:notice).with('[app:proc] message')
      logger.prefix_with('app').prefix_with('proc').notice('message')
    end

    it 'gives prefixed loggers the same level' do
      inner = double('inner', debug: nil, info: nil)
      prefixed = described_class.new(logger: inner, log_level: :info).prefix_with('app')
      prefixed.debug('details')
      prefixed.info('hello')
      expect(inner).not_to have_received(:debug)
      expect(inner).to have_received(:info).with('[app] hello')
    end

    it 'memoizes prefixed loggers' do
      expect(logger.prefix_with('app')).to be(logger.prefix_with('app'))
    end
  end

  describe '#reopen' do
    it 'recreates the underlying logger' do
      logger = described_class.new(log_file: @log_file)
      logger.info('before')
      File.rename(@log_file, "#{@log_file}.1")
      logger.reopen
      logger.info('after')
      expect(File.read(@log_file)).to include('after')
      expect(File.read(@log_file)).not_to include('before')
    end

    it 'reopens syslog' do
      allow(Syslog).to receive(:opened?).and_return(false, true)
      expect(Syslog).to receive(:close).once
      expect(Syslog).to receive(:open).with('bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6).twice.and_return(double('syslog'))
      described_class.new.reopen
    end

    it 'does not require syslog again once it is loaded' do
      allow(Syslog).to receive(:open).and_return(double('syslog'))
      expect_any_instance_of(described_class).not_to receive(:require)
      described_class.new.reopen
    end

    it 'reopens the parent logger of a prefixed logger' do
      logger = described_class.new(log_file: @log_file)
      expect(logger).to receive(:reopen)
      logger.prefix_with('app').reopen
    end
  end
end
