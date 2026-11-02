require 'pathname'
require 'tmpdir'

describe Bluepill::System do
  before do
    described_class.reset_data
  end

  after do
    described_class.reset_data
  end

  def stub_ps(output)
    allow(Bluepill::System).to receive(:ps_axu).and_return(output)
  end

  let(:ps) do
    {
      1 => ['1', '0', '1.5', '100', '01:00', 'init'],
      2 => ['2', '1', '2.5', '200', '02:00', 'child one'],
      3 => ['3', '2', '3.5', '300', '03:00', 'grandchild'],
      4 => ['4', '1', '4.5', '400', '04:00', 'child two'],
    }
  end

  describe '.pid_alive?' do
    it 'is true if process responds to zero signal' do
      expect(Process).to receive(:kill).with(0, 555).and_return(1)
      expect(described_class.pid_alive?(555)).to be true
    end

    it 'is false if process throws exception on zero signal' do
      expect(Process).to receive(:kill).with(0, 555).and_raise(Errno::ESRCH)
      expect(described_class.pid_alive?(555)).to be false
    end

    it 'is true if there is no permission to signal the process' do
      expect(Process).to receive(:kill).with(0, 555).and_raise(Errno::EPERM)
      expect(described_class.pid_alive?(555)).to be true
    end

    it 'is false if signaling raises any other error' do
      expect(Process).to receive(:kill).with(0, nil).and_raise(TypeError)
      expect(described_class.pid_alive?(nil)).to be false
    end
  end

  describe '.started_at' do
    before { allow(Time).to receive(:now).and_return(Time.at(1_000_000)) }

    it "subtracts the process's elapsed time from now" do
      expect(IO).to receive(:popen).with(%w[ps -o etime= -p 555], err: File::NULL).and_return("  1-02:03:04\n")
      expect(described_class.started_at(555)).to eq 1_000_000 - 93_784
    end

    it 'is nil without such a process' do
      expect(IO).to receive(:popen).with(%w[ps -o etime= -p 555], err: File::NULL).and_return('')
      expect(described_class.started_at(555)).to be_nil
    end

    it 'is nil when ps prints only a newline' do
      expect(IO).to receive(:popen).with(%w[ps -o etime= -p 555], err: File::NULL).and_return("\n")
      expect(described_class.started_at(555)).to be_nil
    end

    it "is nil if ps can't run" do
      expect(IO).to receive(:popen).and_raise(Errno::ENOENT)
      expect(described_class.started_at(555)).to be_nil
    end

    it 'only passes ps a pid' do
      expect { described_class.started_at('1; rm -rf /') }.to raise_error(ArgumentError)
    end

    it 'reads what ps prints' do
      pid = ::Process.spawn('sleep', '10')
      begin
        expect(described_class.started_at(pid)).to be_within(2).of(Integer(Time.now))
      ensure
        ::Process.kill('KILL', pid)
        begin
          ::Process.wait(pid)
        rescue Errno::ECHILD
          nil # JRuby 1.7 reaps it already
        end
      end
    end
  end

  describe '.boot_time' do
    it 'is when pid 1 started' do
      expect(described_class).to receive(:started_at).with(1).and_return(42)
      expect(described_class.boot_time).to eq 42
    end
  end

  describe '.cpu_usage' do
    before { stub_ps(ps) }

    it 'is nil for an unknown pid' do
      expect(described_class.cpu_usage(99, true)).to be_nil
    end

    it 'returns the cpu usage of the process' do
      expect(described_class.cpu_usage(2, false)).to eq(2.5)
    end

    it 'includes the cpu usage of all descendants' do
      expect(described_class.cpu_usage(1, true)).to eq(12.0)
    end

    it 'skips children that are missing from ps output' do
      allow(described_class).to receive(:get_children).with(1).and_return([2, 99])
      expect(described_class.cpu_usage(1, true)).to eq(4.0)
    end
  end

  describe '.memory_usage' do
    before { stub_ps(ps) }

    it 'is nil for an unknown pid' do
      expect(described_class.memory_usage(99, true)).to be_nil
    end

    it 'returns the memory usage of the process' do
      expect(described_class.memory_usage(2, false)).to be(200.0)
    end

    it 'includes the memory usage of all descendants' do
      expect(described_class.memory_usage(1, true)).to be(1000.0)
    end

    it 'skips children that are missing from ps output' do
      allow(described_class).to receive(:get_children).with(1).and_return([2, 99])
      expect(described_class.memory_usage(1, true)).to be(300.0)
    end

    it 'parses the memory usage of children as floats' do
      stub_ps(1 => ps[1], 2 => ['2', '1', '2.5', '200.5', '02:00', 'child one'])
      expect(described_class.memory_usage(1, true)).to be(300.5)
    end
  end

  describe '.running_time' do
    before { stub_ps(ps) }

    it 'is nil for an unknown pid' do
      expect(described_class.running_time(99)).to be_nil
    end

    it 'returns the elapsed time in seconds' do
      expect(described_class.running_time(3)).to eq(180)
    end
  end

  describe '.command' do
    before { stub_ps(ps) }

    it 'is nil for an unknown pid' do
      expect(described_class.command(99)).to be_nil
    end

    it 'returns the command of the process' do
      expect(described_class.command(2)).to eq('child one')
    end
  end

  describe '.get_children' do
    before { stub_ps(ps) }

    it 'returns all descendants' do
      expect(described_class.get_children(1)).to eq([2, 4, 3])
    end

    it 'returns an empty array for a process without children' do
      expect(described_class.get_children(3)).to eq([])
    end

    it 'returns an empty array if ps could not be run' do
      allow(described_class).to receive(:ps_axu).and_raise(Bluepill::System::PsError)
      expect(described_class.get_children(1)).to eq([])
    end

    context 'when ps output includes its header row' do
      # "PID".to_i and "PPID".to_i are both 0
      let(:ps) { super().merge(0 => %w[PID PPID %CPU RSS ELAPSED COMMAND]) }

      it 'returns an empty array for a nil pid' do
        expect(described_class.get_children(nil)).to eq([])
      end

      it 'returns an empty array for pid 0' do
        expect(described_class.get_children(0)).to eq([])
      end

      it 'still returns all descendants of a real pid' do
        expect(described_class.get_children(1)).to eq([2, 4, 3])
      end
    end
  end

  describe '.daemonize' do
    let(:rd) { instance_double(IO, close: nil) }
    let(:wr) { instance_double(IO, close: nil, write: nil) }
    let(:logger) { instance_double(Bluepill::Logger) }

    before do
      allow(IO).to receive(:pipe).and_return([rd, wr])
    end

    context 'when in the parent' do
      before do
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(123)
        allow(Process).to receive(:detach)
      end

      it 'detaches the daemon, so it never becomes a zombie' do
        allow(rd).to receive(:read).and_return('456')
        described_class.daemonize('cmd')
        expect(Process).to have_received(:detach).with(123)
      end

      it 'returns the pid of the daemon' do
        allow(rd).to receive(:read).and_return('456')
        expect(described_class.daemonize('cmd')).to eq(456)
        expect(wr).to have_received(:close)
        expect(rd).to have_received(:close)
      end

      it 'returns any positive pid' do
        allow(rd).to receive(:read).and_return('1')
        expect(described_class.daemonize('cmd')).to eq(1)
      end

      it 'returns nil if the child did not report a pid' do
        allow(rd).to receive(:read).and_return('')
        expect(described_class.daemonize('cmd')).to be_nil
      end
    end

    context 'when in the child' do
      let(:pid_file) { '/var/run/test.pid' }
      let(:options) do
        {
          uid: 'user',
          gid: 'group',
          supplementary_groups: ['extra'],
          pid_file: pid_file,
          logger: logger,
          stdin: '/dev/null',
          stdout: 'out.log',
          stderr: 'err.log',
        }
      end

      before do
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(nil)
        allow(described_class).to receive(:drop_privileges)
        allow(described_class).to receive(:redirect_io)
        allow(described_class).to receive(:exit)
        allow(Kernel).to receive(:exec)
        allow(described_class).to receive(:exec).and_raise('exec must be called on Kernel')
        allow(Dir).to receive(:chdir)
        allow(ENV).to receive(:[]=)
        allow(Process).to receive(:exit!)
        allow(described_class).to receive(:exit!).and_raise('exit! must be called on Process')
        allow(File).to receive(:write).with(pid_file, anything)
        allow(Bluepill::Daemonize).to receive(:call_as_daemon) do |block, _|
          block.call
          789
        end
      end

      it 'exits if the pid file cannot be written' do
        expect(described_class).to receive(:can_write_pid_file).with(pid_file, logger).and_return(false)
        expect(described_class).to receive(:exit).with(no_args).and_raise(SystemExit)
        expect { described_class.daemonize('cmd', options) }.to raise_error(SystemExit)
        expect(rd).to have_received(:close)
        expect(described_class).to have_received(:drop_privileges).with('user', 'group', ['extra'])
        expect(Bluepill::Daemonize).not_to have_received(:call_as_daemon)
      end

      it 'runs without options' do
        expect(described_class).to receive(:can_write_pid_file).with(nil, nil).and_return(false)
        expect(described_class).to receive(:exit).with(no_args).and_raise(SystemExit)
        expect { described_class.daemonize('cmd') }.to raise_error(SystemExit)
        expect(described_class).to have_received(:drop_privileges).with(nil, nil, nil)
      end

      it 'does not redirect io that is not configured' do
        allow(described_class).to receive(:can_write_pid_file).and_return(true)
        described_class.daemonize('cmd', pid_file: pid_file, logger: logger)
        expect(described_class).to have_received(:redirect_io).with(nil, nil, nil)
      end

      it 'writes any positive pid to the pid file' do
        allow(described_class).to receive(:can_write_pid_file).and_return(true)
        allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(1)
        described_class.daemonize('cmd', options)
        expect(File).to have_received(:write).with(pid_file, '1')
        expect(wr).to have_received(:write).with(1)
      end

      it 'execs the command as a daemon and reports its pid' do
        allow(described_class).to receive(:can_write_pid_file).and_return(true)
        described_class.daemonize('echo "hello world"', options)
        expect(Dir).not_to have_received(:chdir)
        expect(ENV).not_to have_received(:[]=)
        expect(described_class).to have_received(:redirect_io).with(File::NULL, 'out.log', 'err.log')
        expect(Kernel).to have_received(:exec).with('echo', 'hello world')
        expect(described_class).to have_received(:exit).with(no_args)
        expect(Bluepill::Daemonize).to have_received(:call_as_daemon).with(kind_of(Proc), 'echo "hello world"')
        expect(File).to have_received(:write).with(pid_file, '789')
        expect(wr).to have_received(:write).with(789)
        expect(wr).to have_received(:close)
        expect(Process).to have_received(:exit!).with(true)
      end

      it 'does not write a pid of 0 to the pid file' do
        allow(described_class).to receive(:can_write_pid_file).and_return(true)
        allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(0)
        described_class.daemonize('cmd', options)
        expect(File).not_to have_received(:write)
        expect(wr).to have_received(:write).with(0)
      end

      it 'changes directory and sets the environment' do
        allow(described_class).to receive(:can_write_pid_file).and_return(true)
        options[:working_dir] = Pathname.new('/tmp/work')
        options[:environment] = {FOO: 1}
        described_class.daemonize('cmd', options)
        expect(ENV).to have_received(:[]=).with('PWD', '/tmp/work')
        expect(Dir).to have_received(:chdir).with('/tmp/work')
        expect(ENV).to have_received(:[]=).with('FOO', '1')
      end
    end
  end

  describe '.delete_if_exists' do
    it 'does nothing for a nil filename' do
      expect(File).not_to receive(:unlink)
      described_class.delete_if_exists(nil)
    end

    it 'does nothing if the file does not exist' do
      expect(File).to receive(:exist?).with('missing').and_return(false)
      expect(File).not_to receive(:unlink)
      described_class.delete_if_exists('missing')
    end

    it 'deletes an existing file' do
      Dir.mktmpdir do |dir|
        filename = File.join(dir, 'file')
        File.write(filename, 'x')
        described_class.delete_if_exists(filename)
        expect(File.exist?(filename)).to be false
      end
    end

    it 'ignores files that disappear before deletion' do
      allow(File).to receive(:exist?).with('file').and_return(true)
      expect(File).to receive(:unlink).with('file').and_raise(Errno::ENOENT)
      expect { described_class.delete_if_exists('file') }.not_to raise_error
    end

    it 'retries and then warns when permission is denied' do
      allow(File).to receive(:exist?).with('file').and_return(true)
      expect(File).to receive(:unlink).with('file').exactly(3).times.and_raise(Errno::EACCES)
      expect($stderr).to receive(:puts).with('Warning: permission denied trying to delete file')
      described_class.delete_if_exists('file')
    end
  end

  describe '.execute_blocking' do
    let(:rd) { instance_double(IO, close: nil) }
    let(:wr) { instance_double(IO, close: nil, write: nil) }

    context 'when in the parent' do
      let(:waiter) { instance_double(Thread, join: nil) }

      before do
        allow(IO).to receive(:pipe).and_return([rd, wr])
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(123)
        allow(Process).to receive(:detach).with(123).and_return(waiter)
      end

      it 'returns the result reported by the child' do
        result = {exit_code: 1, stdout: 'out', stderr: 'err'}
        allow(rd).to receive(:read).and_return(Marshal.dump(result))
        expect(described_class.execute_blocking('cmd')).to eq(result)
        expect(wr).to have_received(:close)
        expect(rd).to have_received(:close)
      end

      it 'returns an empty successful result if the child reported nothing' do
        allow(rd).to receive(:read).and_return('')
        expect(described_class.execute_blocking('cmd')).to eq(exit_code: 0, stdout: '', stderr: '')
      end

      it 'waits for the child to be reaped' do
        allow(rd).to receive(:read).and_return('')
        described_class.execute_blocking('cmd')
        expect(Process).to have_received(:detach).with(123)
        expect(waiter).to have_received(:join)
      end

      it "doesn't kill a command that finishes within its timeout" do
        expect(IO).to receive(:select).with([rd], nil, nil, 2.5).and_return([[rd], [], []])
        allow(rd).to receive(:read).and_return('')
        expect(Process).not_to receive(:kill)
        expect(described_class.execute_blocking('cmd', timeout: 2.5)).to eq(exit_code: 0, stdout: '', stderr: '')
      end

      it "kills the command's process group when it runs past its timeout" do
        expect(IO).to receive(:select).with([rd], nil, nil, 2.0).and_return(nil)
        expect(Process).to receive(:kill).with('KILL', -123)
        expect(rd).not_to receive(:read)
        expect { described_class.execute_blocking('cmd', timeout: 2) }.
          to raise_error(Timeout::Error, 'cmd took longer than 2 seconds')
        expect(rd).to have_received(:close)
      end

      it 'gives IO.select a timeout it can read, from a duration too' do
        expect(IO).to receive(:select).with([rd], nil, nil, an_instance_of(Float)).and_return([[rd], [], []])
        allow(rd).to receive(:read).and_return('')
        described_class.execute_blocking('cmd', timeout: 2.seconds)
      end

      it 'times out even if the command has just finished' do
        allow(IO).to receive(:select).and_return(nil)
        allow(Process).to receive(:kill).with('KILL', -123).and_raise(Errno::ESRCH)
        expect { described_class.execute_blocking('cmd', timeout: 2) }.to raise_error(Timeout::Error)
      end

      it 'reaps the child and closes the pipe if interrupted by a timeout' do
        allow(rd).to receive(:read).and_raise(Timeout::Error)
        expect { described_class.execute_blocking('cmd') }.to raise_error(Timeout::Error)
        expect(Process).to have_received(:detach).with(123)
        expect(rd).to have_received(:close)
        expect(waiter).not_to have_received(:join)
      end
    end

    it 'kills a command that hangs, and what it started', if: RUBY_ENGINE == 'ruby' do
      Dir.mktmpdir do |dir|
        pid_file = File.join(dir, 'pid')
        # The command starts a sleep of its own, and hangs
        cmd = %(#{RbConfig.ruby} -e "File.write('#{pid_file}', Process.spawn('sleep', '30').to_s)\nsleep 30")
        expect { described_class.execute_blocking(cmd, timeout: 2) }.to raise_error(Timeout::Error)
        sleep_pid = Integer(File.read(pid_file))
        # Killed, and reaped by init, since the command that started it is gone
        Timeout.timeout(5) { sleep 0.1 while described_class.pid_alive?(sleep_pid) }
        expect(described_class.pid_alive?(sleep_pid)).to be false
      end
    end

    context 'when in the child' do
      let(:out_rd) { instance_double(IO, close: nil, read: 'out') }
      let(:out_wr) { instance_double(IO, close: nil) }
      let(:err_rd) { instance_double(IO, close: nil, read: 'err') }
      let(:err_wr) { instance_double(IO, close: nil, puts: nil, closed?: false) }
      let(:status) { instance_double(Process::Status, exitstatus: 2) }
      let(:options) { {uid: 'user', gid: 'group', supplementary_groups: ['extra']} }

      before do
        allow(IO).to receive(:pipe).and_return([rd, wr], [out_rd, out_wr], [err_rd, err_wr])
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(nil)
        allow(described_class).to receive(:fork) do |&block|
          block.call
          456
        end
        allow(described_class).to receive(:drop_privileges)
        allow(described_class).to receive(:exit)
        allow(Dir).to receive(:chdir)
        allow(ENV).to receive(:[]=)
        allow(STDIN).to receive(:reopen)
        allow(STDOUT).to receive(:reopen)
        allow(STDERR).to receive(:reopen)
        allow(STDERR).to receive(:puts)
        allow(Kernel).to receive(:exec)
        allow(described_class).to receive(:exec).and_raise('exec must be called on Kernel')
        allow(Process).to receive(:waitpid2).with(456).and_return([456, status])
        allow(Process).to receive(:exit!)
      end

      it 'leads a process group of its own with a timeout' do
        expect(Process).to receive(:setpgid).with(0, 0)
        described_class.execute_blocking('echo', timeout: 5)
      end

      it "stays in bluepill's process group without a timeout" do
        expect(Process).not_to receive(:setpgid)
        described_class.execute_blocking('echo')
      end

      it 'execs the command and reports its output and exit code' do
        described_class.execute_blocking('echo "hello world"', options)
        expect(rd).to have_received(:close)
        expect(described_class).to have_received(:drop_privileges).with('user', 'group', ['extra'])
        expect(Dir).not_to have_received(:chdir)
        expect(ENV).not_to have_received(:[]=)
        expect(wr).to have_received(:close).twice
        expect(STDIN).to have_received(:reopen).with(File::NULL)
        expect(STDOUT).to have_received(:reopen).with(out_wr)
        expect(STDERR).to have_received(:reopen).with(err_wr)
        expect(Kernel).to have_received(:exec).with('echo', 'hello world')
        expect(out_wr).to have_received(:close).twice
        expect(err_wr).to have_received(:close).twice
        expect(out_rd).to have_received(:close).twice
        expect(err_rd).to have_received(:close).twice
        expect(wr).to have_received(:write).with(Marshal.dump(stdout: 'out', stderr: 'err', exit_code: 2))
        expect(Process).to have_received(:exit!).with(no_args)
      end

      it 'runs without options' do
        described_class.execute_blocking('cmd')
        expect(described_class).to have_received(:drop_privileges).with(nil, nil, nil)
        expect(Kernel).to have_received(:exec).with('cmd')
      end

      it 'still exits if the parent stopped waiting for the result' do
        allow(wr).to receive(:write).and_raise(Errno::EPIPE)
        described_class.execute_blocking('cmd', options)
        expect(wr).to have_received(:close).twice
        expect(Process).to have_received(:exit!).with(no_args)
      end

      it 'changes directory and sets the environment' do
        options[:working_dir] = Pathname.new('/tmp/work')
        options[:environment] = {FOO: 1}
        described_class.execute_blocking('cmd', options)
        expect(ENV).to have_received(:[]=).with('PWD', '/tmp/work')
        expect(Dir).to have_received(:chdir).with('/tmp/work')
        expect(ENV).to have_received(:[]=).with('FOO', '1')
      end

      it 'reports exceptions on the stderr pipe if it is still open' do
        allow(described_class).to receive(:drop_privileges).and_raise(ArgumentError, 'no such user')
        described_class.execute_blocking('cmd', options)
        expect(err_wr).to have_received(:puts).with('Exception in grandchild: no such user.')
        expect(err_wr).to have_received(:puts).with(kind_of(Array))
        expect(Kernel).not_to have_received(:exec)
        expect(described_class).to have_received(:exit).with(1)
      end

      it 'reports exceptions on STDERR if the stderr pipe is closed' do
        allow(err_wr).to receive(:closed?).and_return(true)
        allow(Kernel).to receive(:exec).and_raise(Errno::ENOENT, 'cmd')
        described_class.execute_blocking('cmd', options)
        expect(STDERR).to have_received(:puts).with('Exception in grandchild: No such file or directory - cmd.')
        expect(STDERR).to have_received(:puts).with(kind_of(Array))
        expect(err_wr).not_to have_received(:puts)
        expect(described_class).to have_received(:exit).with(1)
      end
    end
  end

  describe '.store' do
    it 'is Hash' do
      expect(described_class.store).to be_a(Hash)
    end

    it 'returns the same Hash on every call' do
      expect(described_class.store).to equal(described_class.store)
    end

    it 'stores assigned pairs' do
      described_class.store[:somekey] = 10
      expect(described_class.store[:somekey]).to be(10)
    end
  end

  describe '.reset_data' do
    it 'clears the #store' do
      described_class.store[:anotherkey] = 'Lorem ipsum dolor sit amet.'
      described_class.reset_data
      expect(described_class.store).to be_empty
    end

    it 'leaves an empty #store empty' do
      described_class.reset_data
      expect(described_class.store).to be_empty
    end
  end

  describe '.ps_axu' do
    let(:output) do
      [
        '  PID  PPID  %CPU    RSS     ELAPSED ARGS',
        '    1     0   0.0   1234 10-01:02:03 /sbin/init',
        '  321     1  12.5  56789       01:02 ruby -e "sleep 1"',
      ].join("\n")
    end

    it 'parses ps output into a hash keyed by pid' do
      expect(described_class).to receive(:`).with('ps -Ao pid,ppid,pcpu,rss,etime,args').once.and_return(output)
      expected = {
        0 => %w[PID PPID %CPU RSS ELAPSED ARGS],
        1 => ['1', '0', '0.0', '1234', '10-01:02:03', '/sbin/init'],
        321 => ['321', '1', '12.5', '56789', '01:02', 'ruby -e "sleep 1"'],
      }
      expect(described_class.ps_axu).to eq(expected)
      expect(described_class.ps_axu).to eq(expected)
    end

    it 'onlies run ps once when called from several threads at once' do
      expect(described_class).to receive(:`).once do
        sleep 0.05
        output
      end
      threads = Array.new(5) { Thread.new { described_class.ps_axu } }
      expect(threads.collect(&:value).uniq.size).to eq(1)
    end

    it "raises a PsError and doesn't retry until the next tick if ps cannot be run" do
      expect(described_class).to receive(:`).once.and_raise(Errno::ENOMEM)
      message = 'Could not run ps: Errno::ENOMEM: Cannot allocate memory'
      expect { described_class.ps_axu }.to raise_error(Bluepill::System::PsError, message)
      expect { described_class.memory_usage(1, false) }.to raise_error(Bluepill::System::PsError, message)
      described_class.reset_data
      expect(described_class).to receive(:`).and_return(output)
      expect(described_class.memory_usage(1, false)).to eq(1234.0)
    end
  end

  describe '.parse_etime' do
    it 'parses etime format' do
      expect(described_class.parse_elapsed_time('400-00:04:01')).to equal(34_560_241)
      expect(described_class.parse_elapsed_time('02:04:02')).to equal(7442)
      expect(described_class.parse_elapsed_time('20:03')).to equal(1203)
      expect(described_class.parse_elapsed_time('invalid')).to equal(0)
    end

    it 'parses fields with a leading zero as decimal' do
      expect(described_class.parse_elapsed_time('08-09:08:09')).to equal(724_089)
    end
  end

  describe '.drop_privileges' do
    let(:home) { ENV.fetch('HOME', nil) }

    before do
      allow(Process).to receive(:groups=)
      allow(Process::Sys).to receive(:setgid)
      allow(Process::Sys).to receive(:setuid)
      allow(ENV).to receive(:[]=)
    end

    it 'does nothing unless running as root' do
      allow(Process::Sys).to receive(:geteuid).and_return(501)
      expect(Etc).not_to receive(:getpwnam)
      described_class.drop_privileges('user', 'group', ['extra'])
      expect(Process::Sys).not_to have_received(:setuid)
    end

    context 'when running as root' do
      before do
        allow(Process::Sys).to receive(:geteuid).and_return(0)
      end

      it 'does nothing without a uid, gid or supplementary groups' do
        described_class.drop_privileges(nil, nil, nil)
        expect(Process).not_to have_received(:groups=)
        expect(Process::Sys).not_to have_received(:setgid)
        expect(Process::Sys).not_to have_received(:setuid)
        expect(ENV).not_to have_received(:[]=)
      end

      it "gives a user the user's own groups, the gid, and the supplementary groups" do
        allow(Etc).to receive(:getpwnam).with('user').and_return(instance_double(Etc::Passwd, name: 'user', uid: 501, gid: 10, dir: '/home/user'))
        allow(Etc).to receive(:getgrnam).with('group').and_return(instance_double(Etc::Group, gid: 20))
        allow(Etc).to receive(:getgrnam).with('extra').and_return(instance_double(Etc::Group, gid: 30))
        allow(Process).to receive(:initgroups)
        allow(Process).to receive(:groups).and_return([10, 20])
        described_class.drop_privileges('user', 'group', ['extra'])
        expect(Process).to have_received(:initgroups).with('user', 20).ordered
        expect(Process).to have_received(:groups=).with([10, 20, 30]).ordered
        expect(Process::Sys).to have_received(:setgid).with(20).ordered
        expect(Process::Sys).to have_received(:setuid).with(501).ordered
        expect(ENV).to have_received(:[]=).with('HOME', '/home/user')
      end

      it "gives a user without a gid the user's primary group" do
        allow(Etc).to receive(:getpwnam).with('user').and_return(instance_double(Etc::Passwd, name: 'user', uid: 501, gid: 10, dir: '/home/user'))
        allow(Process).to receive(:initgroups)
        described_class.drop_privileges('user', nil, [])
        expect(Process).to have_received(:initgroups).with('user', 10)
        expect(Process).not_to have_received(:groups=)
        expect(Process::Sys).to have_received(:setgid).with(10)
        expect(Process::Sys).to have_received(:setuid).with(501)
        expect(ENV).to have_received(:[]=).with('HOME', '/home/user')
      end

      it 'keeps the home directory if the user has none' do
        allow(Etc).to receive(:getpwnam).with('user').and_return(instance_double(Etc::Passwd, name: 'user', uid: 501, gid: 10, dir: nil))
        allow(Process).to receive(:initgroups)
        described_class.drop_privileges('user', nil, [])
        expect(Process::Sys).to have_received(:setuid).with(501)
        expect(ENV).not_to have_received(:[]=)
      end

      it 'uses only the gid and supplementary groups without a uid' do
        allow(Etc).to receive(:getgrnam).with('group').and_return(instance_double(Etc::Group, gid: 20))
        allow(Etc).to receive(:getgrnam).with('extra').and_return(instance_double(Etc::Group, gid: 30))
        allow(Process).to receive(:groups).and_return([20])
        expect(Process).not_to receive(:initgroups)
        described_class.drop_privileges(nil, 'group', ['extra'])
        expect(Process).to have_received(:groups=).with([20]).ordered
        expect(Process).to have_received(:groups=).with([20, 30]).ordered
        expect(Process::Sys).to have_received(:setgid).with(20)
        expect(Process::Sys).not_to have_received(:setuid)
        expect(ENV).not_to have_received(:[]=)
      end

      it "adds supplementary groups to bluepill's own without a uid or gid" do
        allow(Etc).to receive(:getgrnam).with('extra').and_return(instance_double(Etc::Group, gid: 30))
        allow(Process).to receive(:groups).and_return([0])
        described_class.drop_privileges(nil, nil, ['extra'])
        expect(Process).to have_received(:groups=).with([0, 30])
        expect(Process::Sys).not_to have_received(:setgid)
        expect(Process::Sys).not_to have_received(:setuid)
      end
    end
  end

  describe '.can_write_pid_file' do
    let(:logger) { instance_double(Bluepill::Logger) }

    it 'is true if the pid file can be written' do
      Dir.mktmpdir do |dir|
        pid_file = File.join(dir, 'test.pid')
        expect(described_class.can_write_pid_file(pid_file, logger)).to be true
        expect(File.exist?(pid_file)).to be false
      end
    end

    it 'logs the error and is false if the pid file cannot be written' do
      Dir.mktmpdir do |dir|
        pid_file = File.join(dir, 'missing', 'test.pid')
        message = begin
          FileUtils.touch(pid_file)
        rescue Errno::ENOENT => e
          "Errno::ENOENT - #{e.message}"
        end
        expect(logger).to receive(:warning).with(message)
        expect(logger).to receive(:warning).at_least(:once).with(kind_of(String))
        expect(described_class.can_write_pid_file(pid_file, logger)).to be false
      end
    end
  end

  describe '.redirect_io' do
    before do
      allow($stdin).to receive(:reopen)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
    end

    it 'does not redirect anything without paths' do
      described_class.redirect_io(nil, nil, nil)
      expect($stdin).not_to have_received(:reopen)
      expect($stdout).not_to have_received(:reopen)
      expect($stderr).not_to have_received(:reopen)
    end

    it 'redirects stdout and stderr to the same file' do
      described_class.redirect_io('in', 'out.log', 'out.log')
      expect($stdin).to have_received(:reopen).with('in')
      expect($stdout).to have_received(:reopen).with('out.log', 'a')
      expect($stderr).to have_received(:reopen).with($stdout)
    end

    it 'redirects stdout and stderr to different files' do
      described_class.redirect_io(nil, 'out.log', 'err.log')
      expect($stdout).to have_received(:reopen).with('out.log', 'a')
      expect($stderr).to have_received(:reopen).with('err.log', 'a')
    end

    it 'redirects only stderr' do
      described_class.redirect_io(nil, nil, 'err.log')
      expect($stdout).not_to have_received(:reopen)
      expect($stderr).to have_received(:reopen).with('err.log', 'a')
    end
  end
end
