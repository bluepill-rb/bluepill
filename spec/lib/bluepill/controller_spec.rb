require 'tmpdir'

describe Bluepill::Controller do
  let(:base_dir) { Dir.mktmpdir }
  let(:controller) { described_class.new(base_dir: base_dir, log_file: '/var/log/bluepill.log') }

  after { FileUtils.remove_entry(base_dir) }

  def touch(path, contents = '')
    File.write(File.join(base_dir, path), contents)
  end

  # Leave an application's socket, and its pid file unless pid is nil
  def touch_app(name, pid = nil)
    touch("socks/#{name}.sock")
    touch("pids/#{name}.pid", pid) if pid
  end

  def files_left
    Dir[File.join(base_dir, '*', '*')]
  end

  def exit_with(status)
    raise_error(an_instance_of(SystemExit).and(having_attributes(status: status)))
  end

  def stub_daemon(command, response)
    allow(Bluepill::Socket).to receive(:client_command).
      with(base_dir, 'app', 'version').and_return(Bluepill::Version)
    allow(Bluepill::Socket).to receive(:client_command).
      with(base_dir, 'app', command).and_return(response)
  end

  describe '#initialize' do
    it 'keeps its options and the directories in the base dir' do
      expect(controller).to have_attributes(
        log_file: '/var/log/bluepill.log', base_dir: base_dir,
        sockets_dir: File.join(base_dir, 'socks'), pids_dir: File.join(base_dir, 'pids')
      )
    end

    it 'creates the directories' do
      controller
      expect(%w[socks pids].collect { |dir| File.directory?(File.join(base_dir, dir)) }).to eq([true, true])
    end

    context 'with applications' do
      before { controller }

      it 'keeps the files of a running application' do
        touch_app('app', '123')
        allow(Bluepill::System).to receive(:pid_alive?).with(123).and_return(true)
        described_class.new(base_dir: base_dir)
        expect(files_left).to contain_exactly(File.join(base_dir, 'socks', 'app.sock'), File.join(base_dir, 'pids', 'app.pid'))
      end

      it 'keeps checking applications after a running one' do
        touch_app('a', '123')
        touch_app('b')
        allow(Bluepill::System).to receive(:pid_alive?).with(123).and_return(true)
        described_class.new(base_dir: base_dir)
        expect(controller.running_applications).to eq(['a'])
      end

      it 'removes the files of an application that is not running' do
        touch_app('dead', '456')
        allow(Bluepill::System).to receive(:pid_alive?).with(456).and_return(false)
        described_class.new(base_dir: base_dir)
        expect(files_left).to eq([])
      end

      it 'removes the socket of an application without a pid file' do
        touch_app('nopid')
        described_class.new(base_dir: base_dir)
        expect(files_left).to eq([])
      end

      it 'removes the files of an application with an empty pid file' do
        touch_app('empty', '')
        described_class.new(base_dir: base_dir)
        expect(files_left).to eq([])
      end
    end
  end

  describe '#running_applications' do
    it 'lists the applications that have a socket' do
      controller
      touch('socks/app.sock')
      touch('socks/other.txt')
      expect(controller.running_applications).to eq(['app'])
    end
  end

  describe '#handle_command' do
    it 'prints the status' do
      stub_daemon('status:web', "web:\n")
      expect { controller.handle_command('app', 'status', 'web') }.to output("web:\n").to_stdout
    end

    it 'prints the status of every process' do
      stub_daemon('status', "web:\n")
      expect { controller.handle_command('app', 'status') }.to output("web:\n").to_stdout
    end

    describe 'process commands' do
      it 'prints the affected processes' do
        stub_daemon('start:web', ['web:first', 'web:second'])
        expect { controller.handle_command('app', 'start', 'web') }.to output(
          "Sent start to:\n  web:first\n  web:second\n"
        ).to_stdout
      end

      it 'says when no process was affected' do
        stub_daemon('stop', [])
        expect { controller.handle_command('app', 'stop') }.to output("No processes effected\n").to_stdout
      end
    end

    it 'exits on an unknown command' do
      expect { controller.handle_command('app', 'bogus') }.to exit_with(1).and output(
        "Unknown command `bogus` (or application `bogus` has not been loaded yet)\n"
      ).to_stderr
    end
  end

  describe '#handle_command quit' do
    before do
      controller
      write_pid('789')
      allow(Bluepill::System).to receive(:pid_alive?).and_return(false)
      allow(::Process).to receive(:kill)
      allow(controller).to receive(:puts)
    end

    def write_pid(pid)
      touch('pids/app.pid', pid)
    end

    def quit
      controller.handle_command('app', 'quit')
    end

    context 'when the daemon is running' do
      before do
        allow(Bluepill::System).to receive(:pid_alive?).with(789).and_return(true)
        quit
      end

      it 'kills it' do
        expect(::Process).to have_received(:kill).with('TERM', 789)
      end

      it 'says so' do
        expect(controller).to have_received(:puts).with('Killing bluepilld[789]')
      end
    end

    context 'when the daemon has pid 1, as in a container' do
      before do
        write_pid('1')
        allow(Bluepill::System).to receive(:pid_alive?).with(1).and_return(true)
        quit
      end

      it 'kills it' do
        expect(::Process).to have_received(:kill).with('TERM', 1)
      end

      it 'says so' do
        expect(controller).to have_received(:puts).with('Killing bluepilld[1]')
      end
    end

    context 'without a pid file' do
      before do
        File.delete(File.join(base_dir, 'pids', 'app.pid'))
        quit
      end

      it 'says the daemon is not running' do
        expect(controller).to have_received(:puts).with('bluepilld[false] not running')
      end

      it 'does not check a pid' do
        expect(Bluepill::System).not_to have_received(:pid_alive?)
      end
    end

    context 'when the daemon is not running' do
      before { quit }

      it 'says so' do
        expect(controller).to have_received(:puts).with('bluepilld[789] not running')
      end

      it 'checks its pid' do
        expect(Bluepill::System).to have_received(:pid_alive?).with(789)
      end

      it 'does not kill it' do
        expect(::Process).not_to have_received(:kill)
      end
    end

    ['', 'garbage'].each do |contents|
      context "when the pid file holds #{contents.inspect}" do
        before do
          write_pid(contents)
          quit
        end

        it 'says the daemon is not running' do
          expect(controller).to have_received(:puts).with('bluepilld[false] not running')
        end

        it 'does not check a pid' do
          expect(Bluepill::System).not_to have_received(:pid_alive?)
        end

        it 'does not kill anything' do
          expect(::Process).not_to have_received(:kill)
        end
      end
    end
  end

  describe '#handle_command log' do
    before do
      allow(controller).to receive(:puts)
      allow(Kernel).to receive(:exec)
    end

    context 'with the log file reported by the daemon' do
      before do
        stub_daemon('log_file', '/tmp/app.log')
        controller.handle_command('app', 'log', 'web')
      end

      it 'says what it tails' do
        expect(controller).to have_received(:puts).with('Tailing log for web...')
      end

      it 'tails the log file' do
        expect(Kernel).to have_received(:exec).with("tail -n 100 -f /tmp/app.log | grep -E '\\[.*app:web.*'")
      end
    end

    it 'uses only the first argument as the pattern' do
      stub_daemon('log_file', '/tmp/app.log')
      controller.handle_command('app', 'log', 'web', 'extra')
      expect(Kernel).to have_received(:exec).with("tail -n 100 -f /tmp/app.log | grep -E '\\[.*app:web.*'")
    end

    it 'falls back to its own log file when the daemon logs to syslog' do
      stub_daemon('log_file', nil)
      controller.handle_command('app', :log)
      expect(Kernel).to have_received(:exec).with("tail -n 100 -f /var/log/bluepill.log | grep -E '\\[.*app.*'")
    end

    it 'falls back to its own log file' do
      stub_daemon('log_file', ' ')
      controller.handle_command('app', :log)
      expect(Kernel).to have_received(:exec).with("tail -n 100 -f /var/log/bluepill.log | grep -E '\\[.*app.*'")
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
      expect { controller.send_to_daemon('app', :status) }.to exit_with(8).and output("Received error from server:\n#{error.inspect}\na.rb:1\nb.rb:2\n").to_stderr
    end

    it 'exits when the daemon returns an error without a backtrace' do
      error = RuntimeError.new('boom')
      stub_daemon('status', error)
      expect { controller.send_to_daemon('app', :status) }.to exit_with(8).and output(
        "Received error from server:\n#{error.inspect}\n\n"
      ).to_stderr
    end

    it 'aborts when the daemon refuses the connection' do
      allow(Bluepill::Socket).to receive(:client_command).and_raise(Errno::ECONNREFUSED)
      expect { controller.send_to_daemon('app', :status) }.to exit_with(1).and output(
        "Connection Refused: Server is not running\n"
      ).to_stderr
    end

    it 'aborts when the daemon version differs' do
      stub_daemon('status', 'up')
      allow(Bluepill::Socket).to receive(:client_command).
        with(base_dir, 'app', 'version').and_return('0.0.1')
      expect { controller.send_to_daemon('app', :status) }.to exit_with(1).and output("The running version of your daemon seems to be out of date.\nDaemon Version: 0.0.1, CLI Version: #{Bluepill::Version}\n").to_stderr
    end

    it 'aborts when the daemon does not understand the version command' do
      stub_daemon('status', 'up')
      allow(Bluepill::Socket).to receive(:client_command).
        with(base_dir, 'app', 'version').and_raise(ArgumentError)
      expect { controller.send_to_daemon('app', :status) }.to exit_with(1).and output("The running version of your daemon seems to be out of date.\n").to_stderr
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
