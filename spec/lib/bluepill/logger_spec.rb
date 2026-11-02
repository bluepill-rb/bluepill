require 'syslog'
require 'tmpdir'

describe Bluepill::Logger do
  # A logger that the block can stub before it initializes, such as its
  # require
  def logger_with(options = {})
    logger = described_class.allocate
    yield logger
    logger.send(:initialize, options)
    logger
  end

  let(:dir) { Dir.mktmpdir }
  let(:log_file) { File.join(dir, 'bluepill.log') }

  after { FileUtils.remove_entry(dir) }

  describe '#initialize' do
    it 'logs to syslog without a log file' do
      syslog = class_double(Syslog, info: nil)
      allow(Syslog).to receive(:opened?).and_return(false)
      allow(Syslog).to receive(:close)
      allow(Syslog).to receive(:open).with('bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(syslog)
      described_class.new.info('hello')
      expect(Syslog).not_to have_received(:close)
      expect(Syslog).to have_received(:open)
      expect(syslog).to have_received(:info).with('hello')
    end

    it 'closes an already opened syslog and uses the given identity' do
      allow(Syslog).to receive(:opened?).and_return(true)
      allow(Syslog).to receive(:close)
      allow(Syslog).to receive(:open).with('myapp', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(class_double(Syslog))
      described_class.new(identity: 'myapp')
      expect(Syslog).to have_received(:close).ordered
      expect(Syslog).to have_received(:open).ordered
    end

    it 'explains how to fix a missing syslog library' do
      hide_const('Syslog')
      expect do
        logger_with { |logger| allow(logger).to receive(:require).with('syslog').and_raise(LoadError) }
      end.to raise_error(LoadError, /add gem 'syslog' to your Gemfile or set log_file/)
    end

    it 'does not load syslog when logging to a log file' do
      logger = logger_with(log_file: log_file) { |l| allow(l).to receive(:require) }
      expect(logger).not_to have_received(:require)
    end

    it 'logs to a log file' do
      described_class.new(log_file: log_file).err('something failed')
      expect(File.read(log_file)).to include('ERROR -- : something failed')
    end

    it 'logs to syslog when log_file is nil' do
      allow(Syslog).to receive(:opened?).and_return(false)
      allow(Syslog).to receive(:open).with('bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(class_double(Syslog))
      described_class.new(log_file: nil)
      expect(Syslog).to have_received(:open)
    end

    it 'prefixes messages with the given prefix' do
      inner = instance_double(Bluepill::Logger::LoggerAdapter, info: nil)
      parent = described_class.new(logger: inner)
      described_class.new(logger: parent, prefix: 'app').info('message')
      expect(inner).to have_received(:info).with('[app] message')
    end

    it 'writes to stdout if requested' do
      inner = instance_double(Bluepill::Logger::LoggerAdapter, info: nil)
      allow($stdout).to receive_messages(puts: nil, flush: nil)
      described_class.new(logger: inner, stdout: true).info('message')
      expect($stdout).to have_received(:puts).with('[info]: message').ordered
      expect($stdout).to have_received(:flush).ordered
    end

    it 'does not write to stdout when stdout is false' do
      inner = instance_double(Bluepill::Logger::LoggerAdapter, info: nil)
      allow($stdout).to receive(:puts)
      described_class.new(logger: inner, stdout: false).info('message')
      expect($stdout).not_to have_received(:puts)
    end

    it 'starts without prefixed loggers' do
      expect(described_class.new(logger: instance_double(Bluepill::Logger::LoggerAdapter)).prefix_with('app')).to be_a(described_class)
    end

    it 'uses a given logger' do
      inner = instance_double(Bluepill::Logger::LoggerAdapter, warning: nil)
      described_class.new(logger: inner).warning('careful')
      expect(inner).to have_received(:warning).with('careful')
    end

    context 'with a log_level' do
      let(:inner) { instance_double(Bluepill::Logger::LoggerAdapter, emerg: nil, err: nil, warning: nil, notice: nil, info: nil, debug: nil) }

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
        message = instance_double(Object, to_s: 'message')
        allow($stdout).to receive(:puts)
        logger = described_class.new(logger: inner, log_level: :warning, stdout: true)
        logger.notice(message)
        logger.info(message)
        logger.debug(message)
        expect(message).not_to have_received(:to_s)
        expect($stdout).not_to have_received(:puts)
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
        logger = described_class.new(log_file: log_file, log_level: :err)
        logger.warning('careful')
        logger.err('failed')
        expect(File.read(log_file)).not_to include('careful')
        expect(File.read(log_file)).to include('ERROR -- : failed')
      end

      it 'keeps the stricter of a prefixed logger level and its parent' do
        inner = instance_double(Bluepill::Logger::LoggerAdapter, warning: nil, info: nil, debug: nil)
        parent = described_class.new(logger: inner, log_level: :info)
        described_class.new(logger: parent, prefix: 'app', log_level: :debug).debug('details')
        described_class.new(logger: parent, prefix: 'app', log_level: :warning).info('hello')
        described_class.new(logger: parent, prefix: 'app', log_level: :warning).warning('careful')
        expect(inner).not_to have_received(:debug)
        expect(inner).not_to have_received(:info)
        expect(inner).to have_received(:warning).with('[app] careful')
      end

      it 'echoes prefixed messages to stdout from the parent' do
        inner = instance_double(Bluepill::Logger::LoggerAdapter, info: nil)
        allow($stdout).to receive_messages(puts: nil, flush: nil)
        described_class.new(logger: inner, stdout: true).prefix_with('app').info('hello')
        expect($stdout).to have_received(:puts).with('[info]: [app] hello').ordered
        expect($stdout).to have_received(:flush).ordered
      end

      it 'adds more prefixes after its own' do
        inner = instance_double(Bluepill::Logger::LoggerAdapter, info: nil)
        described_class.new(logger: inner).prefix_with('app').info('hello', ['web', nil])
        expect(inner).to have_received(:info).with('[app:web] hello')
      end

      it 'adds every parent prefix, the outermost first' do
        inner = instance_double(Bluepill::Logger::LoggerAdapter, info: nil)
        app = described_class.new(logger: described_class.new(logger: inner), prefix: 'app')
        described_class.new(logger: app, prefix: 'web').info('hello')
        expect(inner).to have_received(:info).with('[app:web] hello')
      end

      it 'does not echo prefixed messages unless the parent does' do
        inner = instance_double(Bluepill::Logger::LoggerAdapter, info: nil)
        allow($stdout).to receive(:puts)
        described_class.new(logger: described_class.new(logger: inner), prefix: 'app').info('hello')
        expect($stdout).not_to have_received(:puts)
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
      inner = instance_double(Bluepill::Logger::LoggerAdapter, debug: nil)
      allow($stdout).to receive_messages(puts: nil, flush: nil)
      described_class.new(logger: inner, stdout: true).debug('message', ['a', nil, 'b'])
      expect($stdout).to have_received(:puts).with('[debug]: [a:b] message').ordered
      expect($stdout).to have_received(:flush).ordered
      expect(inner).to have_received(:debug).with('[a:b] message')
    end
  end

  describe '#prefix_with' do
    let(:inner) { instance_double(Bluepill::Logger::LoggerAdapter, notice: nil) }
    let(:logger) { described_class.new(logger: inner) }

    it 'prefixes messages' do
      logger.prefix_with('app').prefix_with('proc').notice('message')
      expect(inner).to have_received(:notice).with('[app:proc] message')
    end

    it 'gives prefixed loggers the same level' do
      inner = instance_double(Bluepill::Logger::LoggerAdapter, debug: nil, info: nil)
      prefixed = described_class.new(logger: inner, log_level: :info).prefix_with('app')
      prefixed.debug('details')
      prefixed.info('hello')
      expect(inner).not_to have_received(:debug)
      expect(inner).to have_received(:info).with('[app] hello')
    end

    it 'memoizes prefixed loggers' do
      first = logger.prefix_with('app')
      expect(logger.prefix_with('app')).to be(first)
    end
  end

  describe '#reopen' do
    it 'recreates the underlying logger' do
      logger = described_class.new(log_file: log_file)
      logger.info('before')
      File.rename(log_file, "#{log_file}.1")
      logger.reopen
      logger.info('after')
      expect(File.read(log_file)).to include('after')
      expect(File.read(log_file)).not_to include('before')
    end

    it 'reopens syslog' do
      allow(Syslog).to receive(:opened?).and_return(false, true)
      allow(Syslog).to receive(:close)
      allow(Syslog).to receive(:open).with('bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(class_double(Syslog))
      described_class.new.reopen
      expect(Syslog).to have_received(:close).once
      expect(Syslog).to have_received(:open).twice
    end

    it 'does not require syslog again once it is loaded' do
      allow(Syslog).to receive(:open).and_return(class_double(Syslog))
      logger = logger_with { |l| allow(l).to receive(:require) }
      logger.reopen
      expect(logger).not_to have_received(:require)
    end

    it 'reopens the parent logger of a prefixed logger' do
      logger = described_class.new(log_file: log_file)
      allow(logger).to receive(:reopen)
      logger.prefix_with('app').reopen
      expect(logger).to have_received(:reopen)
    end
  end
end
