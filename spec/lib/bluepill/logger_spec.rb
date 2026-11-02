require 'syslog'
require 'tmpdir'

# A stand-in for the syslog library, for the specs that load it
FAKE_SYSLOG = <<-RUBY.freeze
  module Syslog
    LOG_PID = 1
    LOG_LOCAL6 = 176

    def self.opened?
      false
    end

    def self.open(*)
      self
    end
  end
RUBY

describe Bluepill::Logger do
  # Make the next require 'syslog' in the block load a fake syslog.rb that
  # runs code: put it first on the load path, and take the real syslog out
  # of $LOADED_FEATURES until the block is done
  def with_fake_syslog(code)
    fake_dir = Dir.mktmpdir
    File.write(File.join(fake_dir, 'syslog.rb'), code)
    loaded = $LOADED_FEATURES.select { |feature| File.basename(feature, '.*') == 'syslog' }
    $LOAD_PATH.unshift(fake_dir)
    $LOADED_FEATURES.reject! { |feature| loaded.include?(feature) }
    yield
  ensure
    $LOAD_PATH.delete(fake_dir)
    $LOADED_FEATURES.reject! { |feature| feature.include?(File.basename(fake_dir)) }
    $LOADED_FEATURES.concat(loaded)
    FileUtils.remove_entry(fake_dir)
  end

  # Record each method's calls in lines, as [method, *args]
  def record(double, *methods)
    methods.each do |method|
      allow(double).to receive(method) { |*args| lines << [method, *args] }
    end
    double
  end

  # Make Syslog record that it's closed and opened, answering opened? with
  # each of the given values in turn, and give a syslog that records what
  # it logs
  def stub_syslog(*opened)
    allow(Syslog).to receive(:opened?).and_return(*opened)
    record(Syslog, :close)
    syslog = record(class_double(Syslog), :info)
    allow(Syslog).to receive(:open) do |*args|
      lines << [:open, *args]
      syslog
    end
  end

  # Make $stdout record what's written and flushed
  def record_stdout
    record($stdout, :puts, :flush)
  end

  # Move the log file aside, as logrotate does, and reopen the logger
  def rotate(logger)
    File.rename(log_file, "#{log_file}.1")
    logger.reopen
  end

  # The messages in the log file, without its header or each line's start
  def log_file_messages
    File.read(log_file).scan(/ -- : (.*)$/).flatten
  end

  let(:dir) { Dir.mktmpdir }
  let(:log_file) { File.join(dir, 'bluepill.log') }
  let(:lines) { [] }
  let(:sink) { record(instance_double(Bluepill::Logger::LoggerAdapter), *described_class::LOG_METHODS) }

  after { FileUtils.remove_entry(dir) }

  describe '#initialize' do
    it 'logs to syslog without a log file' do
      stub_syslog(false)
      described_class.new.info('hello')
      expect(lines).to eq([[:open, 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6], [:info, 'hello']])
    end

    it 'closes an already opened syslog and uses the given identity' do
      stub_syslog(true)
      described_class.new(identity: 'myapp')
      expect(lines).to eq([[:close], [:open, 'myapp', Syslog::LOG_PID, Syslog::LOG_LOCAL6]])
    end

    it 'loads syslog when it is not loaded yet, and logs to it' do
      hide_const('Syslog')
      with_fake_syslog(FAKE_SYSLOG) do
        expect(described_class.new.sink).to eq([Syslog])
      end
    end

    it 'explains how to fix a missing syslog library' do
      hide_const('Syslog')
      with_fake_syslog("raise LoadError, 'cannot load such file -- syslog'\n") do
        expect { described_class.new }.to raise_error(LoadError, /add gem 'syslog' to your Gemfile or set log_file/)
      end
    end

    it 'does not load syslog when logging to a log file' do
      hide_const('Syslog')
      with_fake_syslog("raise 'bluepill loaded syslog'\n") do
        expect { described_class.new(log_file: log_file) }.not_to raise_error
      end
    end

    it 'logs to a log file' do
      described_class.new(log_file: log_file).err('something failed')
      expect(File.read(log_file)).to include('ERROR -- : something failed')
    end

    it 'logs to syslog when log_file is nil' do
      stub_syslog(false)
      described_class.new(log_file: nil)
      expect(lines).to eq([[:open, 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6]])
    end

    it 'prefixes messages with the given prefix' do
      parent = described_class.new(logger: sink)
      described_class.new(logger: parent, prefix: 'app').info('message')
      expect(lines).to eq([[:info, '[app] message']])
    end

    it 'writes to stdout if requested' do
      record_stdout
      described_class.new(logger: sink, stdout: true).info('message')
      expect(lines).to eq([[:puts, '[info]: message'], [:flush], [:info, 'message']])
    end

    it 'does not write to stdout when stdout is false' do
      record_stdout
      described_class.new(logger: sink, stdout: false).info('message')
      expect(lines).to eq([[:info, 'message']])
    end

    it 'starts without prefixed loggers' do
      expect(described_class.new(logger: sink).prefix_with('app')).to be_a(described_class)
    end

    it 'uses a given logger' do
      described_class.new(logger: sink).warning('careful')
      expect(lines).to eq([[:warning, 'careful']])
    end

    context 'with a log_level' do
      it 'logs everything by default' do
        described_class.new(logger: sink).debug('details')
        expect(lines).to eq([[:debug, 'details']])
      end

      it 'logs messages at or above the level' do
        logger = described_class.new(logger: sink, log_level: :warning)
        logger.warning('careful')
        logger.err('failed')
        logger.emerg('down')
        expect(lines).to eq([[:warning, 'careful'], [:err, 'failed'], [:emerg, 'down']])
      end

      it 'drops messages below the level without formatting them' do
        message = record(instance_double(Object), :to_s)
        record_stdout
        logger = described_class.new(logger: sink, log_level: :warning, stdout: true)
        [:notice, :info, :debug].each { |method| logger.public_send(method, message) }
        expect(lines).to eq([])
      end

      it 'logs only the most severe messages at emerg' do
        logger = described_class.new(logger: sink, log_level: :emerg)
        logger.err('failed')
        logger.emerg('down')
        expect(lines).to eq([[:emerg, 'down']])
      end

      it 'takes the level as a string' do
        described_class.new(logger: sink, log_level: 'notice').info('hello')
        expect(lines).to eq([])
      end

      it 'drops messages below the level in a log file' do
        logger = described_class.new(log_file: log_file, log_level: :err)
        logger.warning('careful')
        logger.err('failed')
        expect(log_file_messages).to eq(['failed'])
      end

      it 'keeps the stricter of a prefixed logger level and its parent' do
        parent = described_class.new(logger: sink, log_level: :info)
        described_class.new(logger: parent, prefix: 'app', log_level: :debug).debug('details')
        described_class.new(logger: parent, prefix: 'app', log_level: :warning).info('hello')
        described_class.new(logger: parent, prefix: 'app', log_level: :warning).warning('careful')
        expect(lines).to eq([[:warning, '[app] careful']])
      end

      it 'echoes prefixed messages to stdout from the parent' do
        record_stdout
        described_class.new(logger: sink, stdout: true).prefix_with('app').info('hello')
        expect(lines).to eq([[:puts, '[info]: [app] hello'], [:flush], [:info, '[app] hello']])
      end

      it 'adds more prefixes after its own' do
        described_class.new(logger: sink).prefix_with('app').info('hello', ['web', nil])
        expect(lines).to eq([[:info, '[app:web] hello']])
      end

      it 'adds every parent prefix, the outermost first' do
        app = described_class.new(logger: described_class.new(logger: sink), prefix: 'app')
        described_class.new(logger: app, prefix: 'web').info('hello')
        expect(lines).to eq([[:info, '[app:web] hello']])
      end

      it 'does not echo prefixed messages unless the parent does' do
        record_stdout
        described_class.new(logger: described_class.new(logger: sink), prefix: 'app').info('hello')
        expect(lines).to eq([[:info, '[app] hello']])
      end

      it 'rejects an unknown level' do
        expect { described_class.new(logger: sink, log_level: :verbose) }.to raise_error(
          ArgumentError, 'Unknown log_level :verbose. Use one of: emerg, alert, crit, err, warning, notice, info, debug'
        )
      end
    end
  end

  describe 'log methods' do
    it 'also writes to stdout if requested' do
      record_stdout
      described_class.new(logger: sink, stdout: true).debug('message', ['a', nil, 'b'])
      expect(lines).to eq([[:puts, '[debug]: [a:b] message'], [:flush], [:debug, '[a:b] message']])
    end
  end

  describe '#prefix_with' do
    let(:logger) { described_class.new(logger: sink) }

    it 'prefixes messages' do
      logger.prefix_with('app').prefix_with('proc').notice('message')
      expect(lines).to eq([[:notice, '[app:proc] message']])
    end

    it 'gives prefixed loggers the same level' do
      prefixed = described_class.new(logger: sink, log_level: :info).prefix_with('app')
      prefixed.debug('details')
      prefixed.info('hello')
      expect(lines).to eq([[:info, '[app] hello']])
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
      rotate(logger)
      logger.info('after')
      expect(log_file_messages).to eq(['after'])
    end

    it 'reopens syslog' do
      stub_syslog(false, true)
      described_class.new.reopen
      opened = [:open, 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6]
      expect(lines).to eq([opened, [:close], opened])
    end

    it 'does not require syslog again once it is loaded' do
      stub_syslog(false, true)
      with_fake_syslog("raise 'bluepill loaded syslog again'\n") do
        expect { described_class.new.reopen }.not_to raise_error
      end
    end

    it "reopens the log file of a prefixed logger's parent" do
      logger = described_class.new(log_file: log_file)
      FileUtils.mv(log_file, "#{log_file}.1")
      logger.prefix_with('app').reopen
      logger.info('after')
      expect(File.read(log_file)).to include('after')
    end
  end
end
