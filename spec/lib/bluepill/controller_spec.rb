require 'tmpdir'

describe Bluepill::Controller do
  let(:base_dir) { Dir.mktmpdir }
  let(:controller) { described_class.new(base_dir: base_dir, log_file: '/var/log/bluepill.log') }

  after { FileUtils.remove_entry(base_dir) }

  def touch(*path)
    File.open(File.join(base_dir, *path), 'w') { |f| yield f if block_given? }
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
      expect { controller.handle_command('app', 'status', 'web') }.to output("web:\n").to_stdout
    end

    it 'prints the status of every process' do
      stub_daemon('status', "web:\n")
      expect { controller.handle_command('app', 'status') }.to output("web:\n").to_stdout
    end

    describe 'quit' do
      before do
        controller
        touch('pids', 'app.pid') { |f| f.write('789') }
        allow(Bluepill::System).to receive(:pid_alive?).and_return(false)
        allow(::Process).to receive(:kill)
      end

      def quit
        controller.handle_command('app', 'quit')
      end

      it 'kills a running daemon' do
        allow(Bluepill::System).to receive(:pid_alive?).with(789).and_return(true)
        expect { quit }.to output("Killing bluepilld[789]\n").to_stdout
        expect(::Process).to have_received(:kill).with('TERM', 789)
      end

      it 'kills a daemon with pid 1, as in a container' do
        touch('pids', 'app.pid') { |f| f.write('1') }
        allow(Bluepill::System).to receive(:pid_alive?).with(1).and_return(true)
        expect { quit }.to output("Killing bluepilld[1]\n").to_stdout
        expect(::Process).to have_received(:kill).with('TERM', 1)
      end

      it 'reports a daemon without a pid file' do
        File.delete(File.join(base_dir, 'pids', 'app.pid'))
        expect { quit }.to output("bluepilld[false] not running\n").to_stdout
        expect(Bluepill::System).not_to have_received(:pid_alive?)
      end

      it 'reports a daemon that is not running' do
        expect { quit }.to output("bluepilld[789] not running\n").to_stdout
        expect(Bluepill::System).to have_received(:pid_alive?).with(789)
        expect(::Process).not_to have_received(:kill)
      end

      ['', 'garbage'].each do |contents|
        it "does not kill anything when the pid file holds #{contents.inspect}" do
          touch('pids', 'app.pid') { |f| f.write(contents) }
          expect { quit }.to output("bluepilld[false] not running\n").to_stdout
          expect(Bluepill::System).not_to have_received(:pid_alive?)
          expect(::Process).not_to have_received(:kill)
        end
      end
    end

    describe 'log' do
      before do
        allow(controller).to receive(:puts)
        allow(Kernel).to receive(:exec)
      end

      it 'tails the log file reported by the daemon' do
        stub_daemon('log_file', '/tmp/app.log')
        controller.handle_command('app', 'log', 'web')
        expect(controller).to have_received(:puts).with('Tailing log for web...')
        expect(Kernel).to have_received(:exec).with("tail -n 100 -f /tmp/app.log | grep -E '\\[.*app:web.*'")
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

  describe '#send_to_daemon' do
    it 'returns the response of the daemon' do
      stub_daemon('status:web:first', 'up')
      expect(controller.send_to_daemon('app', :status, 'web', 'first')).to eq('up')
    end

    it 'exits when the daemon returns an error' do
      error = RuntimeError.new('boom')
      error.set_backtrace(['a.rb:1', 'b.rb:2'])
      stub_daemon('status', error)
      expect { controller.send_to_daemon('app', :status) }.to exit_with(8).and output(
        "Received error from server:\n#{error.inspect}\na.rb:1\nb.rb:2\n"
      ).to_stderr
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
      expect { controller.send_to_daemon('app', :status) }.to exit_with(1).and output(
        "The running version of your daemon seems to be out of date.\nDaemon Version: 0.0.1, CLI Version: #{Bluepill::Version}\n"
      ).to_stderr
    end

    it 'aborts when the daemon does not understand the version command' do
      stub_daemon('status', 'up')
      allow(Bluepill::Socket).to receive(:client_command).
        with(base_dir, 'app', 'version').and_raise(ArgumentError)
      expect { controller.send_to_daemon('app', :status) }.to exit_with(1).and output(
        "The running version of your daemon seems to be out of date.\n"
      ).to_stderr
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
