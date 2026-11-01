require 'tmpdir'

describe Bluepill::Controller do
  let(:base_dir) { Dir.mktmpdir }
  let(:controller) { described_class.new(base_dir: base_dir, log_file: '/var/log/bluepill.log') }

  after(:each) { FileUtils.remove_entry(base_dir) }

  def touch(*path)
    File.open(File.join(base_dir, *path), 'w') { |f| yield f if block_given? }
  end

  def stub_daemon(command, response)
    allow(Bluepill::Socket).to receive(:client_command).
      with(base_dir, 'app', 'version').and_return(Bluepill::Version)
    allow(Bluepill::Socket).to receive(:client_command).
      with(base_dir, 'app', command).and_return(response)
  end

  describe '#initialize' do
    it 'sets up the directories' do
      expect(controller.log_file).to eq('/var/log/bluepill.log')
      expect(controller.base_dir).to eq(base_dir)
      expect(controller.sockets_dir).to eq(File.join(base_dir, 'socks'))
      expect(controller.pids_dir).to eq(File.join(base_dir, 'pids'))
      expect(File.directory?(controller.sockets_dir)).to be true
      expect(File.directory?(controller.pids_dir)).to be true
    end

    it 'keeps existing directories' do
      controller
      touch('socks', 'app.sock')
      touch('pids', 'app.pid') { |f| f.write('123') }
      allow(Bluepill::System).to receive(:pid_alive?).with(123).and_return(true)
      described_class.new(base_dir: base_dir)
      expect(File.exist?(File.join(base_dir, 'socks', 'app.sock'))).to be true
    end

    it 'removes the files of applications that are not running' do
      controller
      touch('socks', 'dead.sock')
      touch('pids', 'dead.pid') { |f| f.write('456') }
      touch('socks', 'nopid.sock')
      touch('socks', 'empty.sock')
      touch('pids', 'empty.pid')
      allow(Bluepill::System).to receive(:pid_alive?).with(456).and_return(false)
      described_class.new(base_dir: base_dir)
      expect(Dir[File.join(base_dir, '*', '*')]).to eq([])
    end
  end

  describe '#running_applications' do
    it 'lists the applications that have a socket' do
      controller
      touch('socks', 'app.sock')
      touch('socks', 'other.txt')
      expect(controller.running_applications).to eq(['app'])
    end
  end

  describe '#handle_command' do
    it 'prints the status' do
      stub_daemon('status:web', "web:\n")
      expect(controller).to receive(:puts).with("web:\n")
      controller.handle_command('app', 'status', 'web')
    end

    context 'quit' do
      before(:each) do
        controller
        touch('pids', 'app.pid') { |f| f.write('789') }
      end

      it 'kills a running daemon' do
        allow(Bluepill::System).to receive(:pid_alive?).with(789).and_return(true)
        expect(::Process).to receive(:kill).with('TERM', 789)
        expect(controller).to receive(:puts).with('Killing bluepilld[789]')
        controller.handle_command('app', 'quit')
      end

      it 'reports a daemon that is not running' do
        allow(Bluepill::System).to receive(:pid_alive?).with(789).and_return(false)
        expect(::Process).not_to receive(:kill)
        expect(controller).to receive(:puts).with('bluepilld[789] not running')
        controller.handle_command('app', 'quit')
      end

      ['', 'garbage'].each do |contents|
        it "does not kill anything when the pid file holds #{contents.inspect}" do
          touch('pids', 'app.pid') { |f| f.write(contents) }
          expect(Bluepill::System).not_to receive(:pid_alive?)
          expect(::Process).not_to receive(:kill)
          expect(controller).to receive(:puts).with('bluepilld[false] not running')
          controller.handle_command('app', 'quit')
        end
      end
    end

    context 'log' do
      before(:each) { allow(controller).to receive(:puts) }

      it 'tails the log file reported by the daemon' do
        stub_daemon('log_file', '/tmp/app.log')
        expect(controller).to receive(:puts).with('Tailing log for web...')
        expect(Kernel).to receive(:exec).with("tail -n 100 -f /tmp/app.log | grep -E '\\[.*app:web.*'")
        controller.handle_command('app', 'log', 'web')
      end

      it 'falls back to its own log file' do
        stub_daemon('log_file', ' ')
        expect(Kernel).to receive(:exec).with("tail -n 100 -f /var/log/bluepill.log | grep -E '\\[.*app.*'")
        controller.handle_command('app', :log)
      end
    end

    context 'process commands' do
      it 'prints the affected processes' do
        stub_daemon('start:web', ['web:first', 'web:second'])
        expect(controller).to receive(:puts).with('Sent start to:').ordered
        expect(controller).to receive(:puts).with('  web:first').ordered
        expect(controller).to receive(:puts).with('  web:second').ordered
        controller.handle_command('app', 'start', 'web')
      end

      it 'says when no process was affected' do
        stub_daemon('stop', [])
        expect(controller).to receive(:puts).with('No processes effected')
        controller.handle_command('app', 'stop')
      end
    end

    it 'exits on an unknown command' do
      expect($stderr).to receive(:puts).with('Unknown command `bogus` (or application `bogus` has not been loaded yet)')
      expect(controller).to receive(:exit).with(1)
      controller.handle_command('app', 'bogus')
    end
  end

  describe '#send_to_daemon' do
    it 'returns the response of the daemon' do
      stub_daemon('status:web:first', 'up')
      expect(controller.send_to_daemon('app', :status, 'web', 'first')).to eq('up')
    end

    it 'exits when the daemon returns an error' do
      error = RuntimeError.new('boom')
      error.set_backtrace(['a.rb:1', 'b.rb:2'])
      stub_daemon('status', error)
      expect($stderr).to receive(:puts).with('Received error from server:').ordered
      expect($stderr).to receive(:puts).with(error.inspect).ordered
      expect($stderr).to receive(:puts).with("a.rb:1\nb.rb:2").ordered
      expect(controller).to receive(:exit).with(8)
      controller.send_to_daemon('app', :status)
    end

    it 'aborts when the daemon refuses the connection' do
      allow(Bluepill::Socket).to receive(:client_command).and_raise(Errno::ECONNREFUSED)
      expect(controller).to receive(:abort).with('Connection Refused: Server is not running')
      controller.send_to_daemon('app', :status)
    end

    it 'aborts when the daemon version differs' do
      stub_daemon('status', 'up')
      allow(Bluepill::Socket).to receive(:client_command).
        with(base_dir, 'app', 'version').and_return('0.0.1')
      expect(controller).to receive(:abort).
        with("The running version of your daemon seems to be out of date.\nDaemon Version: 0.0.1, CLI Version: #{Bluepill::Version}")
      expect(controller.send_to_daemon('app', :status)).to eq('up')
    end

    it 'aborts when the daemon does not understand the version command' do
      stub_daemon('status', 'up')
      allow(Bluepill::Socket).to receive(:client_command).
        with(base_dir, 'app', 'version').and_raise(ArgumentError)
      expect(controller).to receive(:abort).with('The running version of your daemon seems to be out of date.')
      expect(controller.send_to_daemon('app', :status)).to eq('up')
    end
  end

  describe '#grep_pattern' do
    it 'matches the application' do
      expect(controller.grep_pattern('app')).to eq('\[.*app.*')
    end

    it 'matches the application and an escaped query' do
      expect(controller.grep_pattern('app', 'a.b')).to eq('\[.*app:a\.b.*')
    end
  end
end
