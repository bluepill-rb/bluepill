require 'syslog'
require 'tmpdir'

describe Bluepill::Logger do
  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @log_file = File.join(dir, 'bluepill.log')
      example.run
    end
  end

  describe '#initialize' do
    it 'should log to syslog without a log file' do
      syslog = double('syslog')
      allow(Syslog).to receive(:opened?).and_return(false)
      expect(Syslog).not_to receive(:close)
      expect(Syslog).to receive(:open).with('bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(syslog)
      expect(syslog).to receive(:info).with('hello')
      Bluepill::Logger.new.info('hello')
    end

    it 'should close an already opened syslog and use the given identity' do
      allow(Syslog).to receive(:opened?).and_return(true)
      expect(Syslog).to receive(:close)
      expect(Syslog).to receive(:open).with('myapp', Syslog::LOG_PID, Syslog::LOG_LOCAL6).and_return(double('syslog'))
      Bluepill::Logger.new(identity: 'myapp')
    end

    it 'should explain how to fix a missing syslog library' do
      allow_any_instance_of(Bluepill::Logger).to receive(:require).with('syslog').and_raise(LoadError)
      expect { Bluepill::Logger.new }.to raise_error(LoadError, /add gem 'syslog' to your Gemfile or set log_file/)
    end

    it 'should not load syslog when logging to a log file' do
      expect_any_instance_of(Bluepill::Logger).not_to receive(:require)
      Bluepill::Logger.new(log_file: @log_file)
    end

    it 'should log to a log file' do
      Bluepill::Logger.new(log_file: @log_file).err('something failed')
      expect(File.read(@log_file)).to match(/ERROR -- : something failed/)
    end

    it 'should use a given logger' do
      inner = double('inner')
      expect(inner).to receive(:warning).with('careful')
      Bluepill::Logger.new(logger: inner).warning('careful')
    end
  end

  describe 'log methods' do
    it 'should also write to stdout if requested' do
      inner = double('inner', debug: nil)
      expect($stdout).to receive(:puts).with('[debug]: [a:b] message')
      expect($stdout).to receive(:flush)
      Bluepill::Logger.new(logger: inner, stdout: true).debug('message', ['a', nil, 'b'])
      expect(inner).to have_received(:debug).with('[a:b] message')
    end
  end

  describe '#prefix_with' do
    let(:inner) { double('inner') }
    let(:logger) { Bluepill::Logger.new(logger: inner) }

    it 'should prefix messages' do
      expect(inner).to receive(:notice).with('[app:proc] message')
      logger.prefix_with('app').prefix_with('proc').notice('message')
    end

    it 'should memoize prefixed loggers' do
      expect(logger.prefix_with('app')).to be(logger.prefix_with('app'))
    end
  end

  describe '#reopen' do
    it 'should recreate the underlying logger' do
      logger = Bluepill::Logger.new(log_file: @log_file)
      logger.info('before')
      File.rename(@log_file, "#{@log_file}.1")
      logger.reopen
      logger.info('after')
      expect(File.read(@log_file)).to match(/after/)
      expect(File.read(@log_file)).not_to match(/before/)
    end

    it 'should reopen the parent logger of a prefixed logger' do
      logger = Bluepill::Logger.new(log_file: @log_file)
      expect(logger).to receive(:reopen)
      logger.prefix_with('app').reopen
    end
  end
end
