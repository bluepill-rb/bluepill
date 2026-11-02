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
      with(base_dir, 'app', 'version').and_return(Bluepill::Version.to_s)
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
      expect(FileUtils).not_to receive(:mkdir_p)
      described_class.new(base_dir: base_dir)
      expect(File.exist?(File.join(base_dir, 'socks', 'app.sock'))).to be true
    end

    it 'keeps checking applications after a running one' do
      controller
      touch('socks', 'a.sock')
      touch('pids', 'a.pid') { |f| f.write('123') }
      touch('socks', 'b.sock')
      allow(Bluepill::System).to receive(:pid_alive?).with(123).and_return(true)
      described_class.new(base_dir: base_dir)
      expect(controller.running_applications).to eq(['a'])
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

    it 'prints the status of every process' do
      stub_daemon('status', "web:\n")
      expect(controller).to receive(:puts).with("web:\n")
      controller.handle_command('app', 'status')
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

      it 'kills a daemon with pid 1, as in a container' do
        touch('pids', 'app.pid') { |f| f.write('1') }
        allow(Bluepill::System).to receive(:pid_alive?).with(1).and_return(true)
        expect(::Process).to receive(:kill).with('TERM', 1)
        expect(controller).to receive(:puts).with('Killing bluepilld[1]')
        controller.handle_command('app', 'quit')
      end

      it 'reports a daemon without a pid file' do
        File.delete(File.join(base_dir, 'pids', 'app.pid'))
        expect(Bluepill::System).not_to receive(:pid_alive?)
        expect(controller).to receive(:puts).with('bluepilld[false] not running')
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

      def tail(path, pattern)
        ['sh', '-c', 'tail -n 100 -f "$1" | grep -E "$2"', 'sh', path, pattern]
      end

      it 'passes a path with spaces and shell characters to tail as one argument' do
        path = "/tmp/my logs/app's $(touch pwned).log"
        stub_daemon('log_file', path)
        expect(Kernel).to receive(:exec).with(*tail(path, "\\[.*app:it's.*"))
        controller.handle_command('app', 'log', "it's")
      end

      it 'tails the log through a shell that reads the path and pattern as arguments' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "a log's $(name).log")
          File.write(path, "[app:web] one\n[app:db] two\n[app:web] three\n")
          command = tail(path, '\[.*app:web.*')
          command[2] = command[2].sub(' -f', '')
          expect(IO.popen(command, &:read)).to eq("[app:web] one\n[app:web] three\n")
        end
      end

      it 'tails an empty path when neither the daemon nor the CLI has a log file' do
        controller.log_file = nil
        stub_daemon('log_file', nil)
        expect(Kernel).to receive(:exec).with(*tail('', '\[.*app.*'))
        controller.handle_command('app', :log)
      end

      it 'tails the log file reported by the daemon' do
        stub_daemon('log_file', '/tmp/app.log')
        expect(controller).to receive(:puts).with('Tailing log for web...')
        expect(Kernel).to receive(:exec).with(*tail('/tmp/app.log', '\[.*app:web.*'))
        controller.handle_command('app', 'log', 'web')
      end

      it 'uses only the first argument as the pattern' do
        stub_daemon('log_file', '/tmp/app.log')
        expect(Kernel).to receive(:exec).with(*tail('/tmp/app.log', '\[.*app:web.*'))
        controller.handle_command('app', 'log', 'web', 'extra')
      end

      it 'falls back to its own log file when the daemon logs to syslog' do
        stub_daemon('log_file', nil)
        expect(Kernel).to receive(:exec).with(*tail('/var/log/bluepill.log', '\[.*app.*'))
        controller.handle_command('app', :log)
      end

      it 'falls back to its own log file' do
        stub_daemon('log_file', ' ')
        expect(Kernel).to receive(:exec).with(*tail('/var/log/bluepill.log', '\[.*app.*'))
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

    it 'exits when the daemon returns an error without a backtrace' do
      error = RuntimeError.new('boom')
      stub_daemon('status', error)
      allow($stderr).to receive(:puts)
      expect($stderr).to receive(:puts).with('')
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

    it 'goes on when the daemon runs the same version' do
      stub_daemon('status', 'up')
      # What the daemon sends, through Marshal, without stubbing the version
      allow(Bluepill::Socket).to receive(:client_command).
        with(base_dir, 'app', 'version').and_return(Marshal.load(Marshal.dump(Bluepill::Application.allocate.version)))
      expect(controller).not_to receive(:abort)
      expect { expect(controller.send_to_daemon('app', :status)).to eq('up') }.not_to output.to_stderr
    end

    it 'warns and goes on when a daemon from before 0.1.7 answers with its Version module' do
      stub_daemon('status', 'up')
      allow(Bluepill::Socket).to receive(:client_command).
        with(base_dir, 'app', 'version').and_return(Marshal.load(Marshal.dump(Bluepill::Version)))
      expect(controller).not_to receive(:abort)
      expect { expect(controller.send_to_daemon('app', :status)).to eq('up') }.
        to output('The running daemon is older than bluepill 0.1.7, so the CLI cannot check its version. ' \
                  "Run bluepill load again to replace it.\n").to_stderr
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
