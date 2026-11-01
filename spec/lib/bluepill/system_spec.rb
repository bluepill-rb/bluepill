require 'pathname'
require 'tmpdir'

describe Bluepill::System do
  before(:each) do
    Bluepill::System.reset_data
  end

  after(:each) do
    Bluepill::System.reset_data
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

  describe :pid_alive? do
    it 'should be true if process responds to zero signal' do
      expect(Process).to receive(:kill).with(0, 555).and_return(1)
      expect(Bluepill::System.pid_alive?(555)).to be true
    end

    it 'should be false if process throws exception on zero signal' do
      expect(Process).to receive(:kill).with(0, 555).and_raise(Errno::ESRCH)
      expect(Bluepill::System.pid_alive?(555)).to be false
    end

    it 'should be true if there is no permission to signal the process' do
      expect(Process).to receive(:kill).with(0, 555).and_raise(Errno::EPERM)
      expect(Bluepill::System.pid_alive?(555)).to be true
    end

    it 'should be false if signaling raises any other error' do
      expect(Process).to receive(:kill).with(0, nil).and_raise(TypeError)
      expect(Bluepill::System.pid_alive?(nil)).to be false
    end
  end

  describe :cpu_usage do
    before(:each) { stub_ps(ps) }

    it 'should be nil for an unknown pid' do
      expect(Bluepill::System.cpu_usage(99, true)).to be_nil
    end

    it 'should return the cpu usage of the process' do
      expect(Bluepill::System.cpu_usage(2, false)).to eq(2.5)
    end

    it 'should include the cpu usage of all descendants' do
      expect(Bluepill::System.cpu_usage(1, true)).to eq(12.0)
    end

    it 'should skip children that are missing from ps output' do
      allow(Bluepill::System).to receive(:get_children).with(1).and_return([2, 99])
      expect(Bluepill::System.cpu_usage(1, true)).to eq(4.0)
    end
  end

  describe :memory_usage do
    before(:each) { stub_ps(ps) }

    it 'should be nil for an unknown pid' do
      expect(Bluepill::System.memory_usage(99, true)).to be_nil
    end

    it 'should return the memory usage of the process' do
      expect(Bluepill::System.memory_usage(2, false)).to eql(200.0)
    end

    it 'should include the memory usage of all descendants' do
      expect(Bluepill::System.memory_usage(1, true)).to eql(1000.0)
    end

    it 'should skip children that are missing from ps output' do
      allow(Bluepill::System).to receive(:get_children).with(1).and_return([2, 99])
      expect(Bluepill::System.memory_usage(1, true)).to eql(300.0)
    end

    it 'should parse the memory usage of children as floats' do
      stub_ps(1 => ps[1], 2 => ['2', '1', '2.5', '200.5', '02:00', 'child one'])
      expect(Bluepill::System.memory_usage(1, true)).to eql(300.5)
    end
  end

  describe :running_time do
    before(:each) { stub_ps(ps) }

    it 'should be nil for an unknown pid' do
      expect(Bluepill::System.running_time(99)).to be_nil
    end

    it 'should return the elapsed time in seconds' do
      expect(Bluepill::System.running_time(3)).to eq(180)
    end
  end

  describe :command do
    before(:each) { stub_ps(ps) }

    it 'should be nil for an unknown pid' do
      expect(Bluepill::System.command(99)).to be_nil
    end

    it 'should return the command of the process' do
      expect(Bluepill::System.command(2)).to eq('child one')
    end
  end

  describe :get_children do
    before(:each) { stub_ps(ps) }

    it 'should return all descendants' do
      expect(Bluepill::System.get_children(1)).to eq([2, 4, 3])
    end

    it 'should return an empty array for a process without children' do
      expect(Bluepill::System.get_children(3)).to eq([])
    end

    it 'should return an empty array if ps could not be run' do
      allow(Bluepill::System).to receive(:ps_axu).and_raise(Bluepill::System::PsError)
      expect(Bluepill::System.get_children(1)).to eq([])
    end

    context 'when ps output includes its header row' do
      # "PID".to_i and "PPID".to_i are both 0
      let(:ps) { super().merge(0 => %w[PID PPID %CPU RSS ELAPSED COMMAND]) }

      it 'should return an empty array for a nil pid' do
        expect(Bluepill::System.get_children(nil)).to eq([])
      end

      it 'should return an empty array for pid 0' do
        expect(Bluepill::System.get_children(0)).to eq([])
      end

      it 'should still return all descendants of a real pid' do
        expect(Bluepill::System.get_children(1)).to eq([2, 4, 3])
      end
    end
  end

  describe :daemonize do
    let(:rd) { double('rd', close: nil) }
    let(:wr) { double('wr', close: nil, write: nil) }
    let(:logger) { double('logger') }

    before(:each) do
      allow(IO).to receive(:pipe).and_return([rd, wr])
    end

    context 'in the parent' do
      before(:each) do
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(123)
        expect(Process).to receive(:detach).with(123)
      end

      it 'should return the pid of the daemon' do
        allow(rd).to receive(:read).and_return('456')
        expect(Bluepill::System.daemonize('cmd')).to eq(456)
        expect(wr).to have_received(:close)
        expect(rd).to have_received(:close)
      end

      it 'should return any positive pid' do
        allow(rd).to receive(:read).and_return('1')
        expect(Bluepill::System.daemonize('cmd')).to eq(1)
      end

      it 'should return nil if the child did not report a pid' do
        allow(rd).to receive(:read).and_return('')
        expect(Bluepill::System.daemonize('cmd')).to be_nil
      end
    end

    context 'in the child' do
      let(:pid_file) { '/var/run/test.pid' }
      let(:file) { double('file') }
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

      before(:each) do
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(nil)
        allow(Bluepill::System).to receive(:drop_privileges)
        allow(Bluepill::System).to receive(:redirect_io)
        allow(Bluepill::System).to receive(:exit)
        allow(Kernel).to receive(:exec)
        allow(Bluepill::System).to receive(:exec).and_raise('exec must be called on Kernel')
        allow(Dir).to receive(:chdir)
        allow(ENV).to receive(:[]=)
        allow(Process).to receive(:exit!)
        allow(Bluepill::System).to receive(:exit!).and_raise('exit! must be called on Process')
        allow(File).to receive(:open).with(pid_file, 'w').and_yield(file)
        allow(file).to receive(:write)
        allow(Bluepill::Daemonize).to receive(:call_as_daemon) do |block, _|
          block.call
          789
        end
      end

      it 'should exit if the pid file cannot be written' do
        expect(Bluepill::System).to receive(:can_write_pid_file).with(pid_file, logger).and_return(false)
        expect(Bluepill::System).to receive(:exit).with(no_args).and_raise(SystemExit)
        expect { Bluepill::System.daemonize('cmd', options) }.to raise_error(SystemExit)
        expect(rd).to have_received(:close)
        expect(Bluepill::System).to have_received(:drop_privileges).with('user', 'group', ['extra'])
        expect(Bluepill::Daemonize).not_to have_received(:call_as_daemon)
      end

      it 'should run without options' do
        expect(Bluepill::System).to receive(:can_write_pid_file).with(nil, nil).and_return(false)
        expect(Bluepill::System).to receive(:exit).with(no_args).and_raise(SystemExit)
        expect { Bluepill::System.daemonize('cmd') }.to raise_error(SystemExit)
        expect(Bluepill::System).to have_received(:drop_privileges).with(nil, nil, nil)
      end

      it 'should not redirect io that is not configured' do
        allow(Bluepill::System).to receive(:can_write_pid_file).and_return(true)
        Bluepill::System.daemonize('cmd', pid_file: pid_file, logger: logger)
        expect(Bluepill::System).to have_received(:redirect_io).with(nil, nil, nil)
      end

      it 'should write any positive pid to the pid file' do
        allow(Bluepill::System).to receive(:can_write_pid_file).and_return(true)
        allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(1)
        Bluepill::System.daemonize('cmd', options)
        expect(file).to have_received(:write).with(1)
        expect(wr).to have_received(:write).with(1)
      end

      it 'should exec the command as a daemon and report its pid' do
        allow(Bluepill::System).to receive(:can_write_pid_file).and_return(true)
        Bluepill::System.daemonize('echo "hello world"', options)
        expect(Dir).not_to have_received(:chdir)
        expect(ENV).not_to have_received(:[]=)
        expect(Bluepill::System).to have_received(:redirect_io).with('/dev/null', 'out.log', 'err.log')
        expect(Kernel).to have_received(:exec).with('echo', 'hello world')
        expect(Bluepill::System).to have_received(:exit).with(no_args)
        expect(Bluepill::Daemonize).to have_received(:call_as_daemon).with(kind_of(Proc), 'echo "hello world"')
        expect(file).to have_received(:write).with(789)
        expect(wr).to have_received(:write).with(789)
        expect(wr).to have_received(:close)
        expect(Process).to have_received(:exit!).with(true)
      end

      it 'should not write a pid of 0 to the pid file' do
        allow(Bluepill::System).to receive(:can_write_pid_file).and_return(true)
        allow(Bluepill::Daemonize).to receive(:call_as_daemon).and_return(0)
        Bluepill::System.daemonize('cmd', options)
        expect(File).not_to have_received(:open)
        expect(wr).to have_received(:write).with(0)
      end

      it 'should change directory and set the environment' do
        allow(Bluepill::System).to receive(:can_write_pid_file).and_return(true)
        options[:working_dir] = Pathname.new('/tmp/work')
        options[:environment] = {FOO: 1}
        Bluepill::System.daemonize('cmd', options)
        expect(ENV).to have_received(:[]=).with('PWD', '/tmp/work')
        expect(Dir).to have_received(:chdir).with('/tmp/work')
        expect(ENV).to have_received(:[]=).with('FOO', '1')
      end
    end
  end

  describe :delete_if_exists do
    it 'should do nothing for a nil filename' do
      expect(File).not_to receive(:unlink)
      Bluepill::System.delete_if_exists(nil)
    end

    it 'should do nothing if the file does not exist' do
      expect(File).to receive(:exist?).with('missing').and_return(false)
      expect(File).not_to receive(:unlink)
      Bluepill::System.delete_if_exists('missing')
    end

    it 'should delete an existing file' do
      Dir.mktmpdir do |dir|
        filename = File.join(dir, 'file')
        File.open(filename, 'w') { |f| f.write('x') }
        Bluepill::System.delete_if_exists(filename)
        expect(File.exist?(filename)).to be false
      end
    end

    it 'should ignore files that disappear before deletion' do
      allow(File).to receive(:exist?).with('file').and_return(true)
      expect(File).to receive(:unlink).with('file').and_raise(Errno::ENOENT)
      expect { Bluepill::System.delete_if_exists('file') }.not_to raise_error
    end

    it 'should retry and then warn when permission is denied' do
      allow(File).to receive(:exist?).with('file').and_return(true)
      expect(File).to receive(:unlink).with('file').exactly(3).times.and_raise(Errno::EACCES)
      expect($stderr).to receive(:puts).with('Warning: permission denied trying to delete file')
      Bluepill::System.delete_if_exists('file')
    end
  end

  describe :execute_blocking do
    let(:rd) { double('rd', close: nil) }
    let(:wr) { double('wr', close: nil, write: nil) }

    context 'in the parent' do
      let(:waiter) { double('waiter', join: nil) }

      before(:each) do
        allow(IO).to receive(:pipe).and_return([rd, wr])
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(123)
        allow(Process).to receive(:detach).with(123).and_return(waiter)
      end

      it 'should return the result reported by the child' do
        result = {exit_code: 1, stdout: 'out', stderr: 'err'}
        allow(rd).to receive(:read).and_return(Marshal.dump(result))
        expect(Bluepill::System.execute_blocking('cmd')).to eq(result)
        expect(wr).to have_received(:close)
        expect(rd).to have_received(:close)
      end

      it 'should return an empty successful result if the child reported nothing' do
        allow(rd).to receive(:read).and_return('')
        expect(Bluepill::System.execute_blocking('cmd')).to eq(exit_code: 0, stdout: '', stderr: '')
      end

      it 'should wait for the child to be reaped' do
        allow(rd).to receive(:read).and_return('')
        Bluepill::System.execute_blocking('cmd')
        expect(Process).to have_received(:detach).with(123)
        expect(waiter).to have_received(:join)
      end

      it 'should reap the child and close the pipe if interrupted by a timeout' do
        allow(rd).to receive(:read).and_raise(Timeout::Error)
        expect { Bluepill::System.execute_blocking('cmd') }.to raise_error(Timeout::Error)
        expect(Process).to have_received(:detach).with(123)
        expect(rd).to have_received(:close)
        expect(waiter).not_to have_received(:join)
      end
    end

    context 'in the child' do
      let(:out_rd) { double('out_rd', close: nil, read: 'out') }
      let(:out_wr) { double('out_wr', close: nil) }
      let(:err_rd) { double('err_rd', close: nil, read: 'err') }
      let(:err_wr) { double('err_wr', close: nil, puts: nil, closed?: false) }
      let(:status) { double('status', exitstatus: 2) }
      let(:options) { {uid: 'user', gid: 'group', supplementary_groups: ['extra']} }

      before(:each) do
        allow(IO).to receive(:pipe).and_return([rd, wr], [out_rd, out_wr], [err_rd, err_wr])
        allow(Bluepill::Daemonize).to receive(:safefork).and_return(nil)
        allow(Bluepill::System).to receive(:fork) do |&block|
          block.call
          456
        end
        allow(Bluepill::System).to receive(:drop_privileges)
        allow(Bluepill::System).to receive(:exit)
        allow(Dir).to receive(:chdir)
        allow(ENV).to receive(:[]=)
        allow(STDIN).to receive(:reopen)
        allow(STDOUT).to receive(:reopen)
        allow(STDERR).to receive(:reopen)
        allow(STDERR).to receive(:puts)
        allow(Kernel).to receive(:exec)
        allow(Bluepill::System).to receive(:exec).and_raise('exec must be called on Kernel')
        allow(Process).to receive(:waitpid2).with(456).and_return([456, status])
        allow(Process).to receive(:exit!)
      end

      it 'should exec the command and report its output and exit code' do
        Bluepill::System.execute_blocking('echo "hello world"', options)
        expect(rd).to have_received(:close)
        expect(Bluepill::System).to have_received(:drop_privileges).with('user', 'group', ['extra'])
        expect(Dir).not_to have_received(:chdir)
        expect(ENV).not_to have_received(:[]=)
        expect(wr).to have_received(:close).twice
        expect(STDIN).to have_received(:reopen).with('/dev/null')
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

      it 'should run without options' do
        Bluepill::System.execute_blocking('cmd')
        expect(Bluepill::System).to have_received(:drop_privileges).with(nil, nil, nil)
        expect(Kernel).to have_received(:exec).with('cmd')
      end

      it 'should still exit if the parent stopped waiting for the result' do
        allow(wr).to receive(:write).and_raise(Errno::EPIPE)
        Bluepill::System.execute_blocking('cmd', options)
        expect(wr).to have_received(:close).twice
        expect(Process).to have_received(:exit!).with(no_args)
      end

      it 'should change directory and set the environment' do
        options[:working_dir] = Pathname.new('/tmp/work')
        options[:environment] = {FOO: 1}
        Bluepill::System.execute_blocking('cmd', options)
        expect(ENV).to have_received(:[]=).with('PWD', '/tmp/work')
        expect(Dir).to have_received(:chdir).with('/tmp/work')
        expect(ENV).to have_received(:[]=).with('FOO', '1')
      end

      it 'should report exceptions on the stderr pipe if it is still open' do
        allow(Bluepill::System).to receive(:drop_privileges).and_raise(ArgumentError, 'no such user')
        Bluepill::System.execute_blocking('cmd', options)
        expect(err_wr).to have_received(:puts).with('Exception in grandchild: no such user.')
        expect(err_wr).to have_received(:puts).with(kind_of(Array))
        expect(Kernel).not_to have_received(:exec)
        expect(Bluepill::System).to have_received(:exit).with(1)
      end

      it 'should report exceptions on STDERR if the stderr pipe is closed' do
        allow(err_wr).to receive(:closed?).and_return(true)
        allow(Kernel).to receive(:exec).and_raise(Errno::ENOENT, 'cmd')
        Bluepill::System.execute_blocking('cmd', options)
        expect(STDERR).to have_received(:puts).with('Exception in grandchild: No such file or directory - cmd.')
        expect(STDERR).to have_received(:puts).with(kind_of(Array))
        expect(err_wr).not_to have_received(:puts)
        expect(Bluepill::System).to have_received(:exit).with(1)
      end
    end
  end

  describe :store do
    it 'should be Hash' do
      expect(Bluepill::System.store).to be_kind_of(Hash)
    end

    it 'should return same Hash or every call' do
      expect(Bluepill::System.store).to be_equal(Bluepill::System.store)
    end

    it 'should store assigned pairs' do
      Bluepill::System.store[:somekey] = 10
      expect(Bluepill::System.store[:somekey]).to be_eql(10)
    end
  end

  describe :reset_data do
    it 'should clear the #store' do
      Bluepill::System.store[:anotherkey] = 'Lorem ipsum dolor sit amet.'
      Bluepill::System.reset_data
      expect(Bluepill::System.store).to be_empty
    end

    it 'should leave an empty #store empty' do
      Bluepill::System.reset_data
      expect(Bluepill::System.store).to be_empty
    end
  end

  describe :ps_axu do
    let(:output) do
      [
        '  PID  PPID  %CPU    RSS     ELAPSED ARGS',
        '    1     0   0.0   1234 10-01:02:03 /sbin/init',
        '  321     1  12.5  56789       01:02 ruby -e "sleep 1"',
      ].join("\n")
    end

    it 'should parse ps output into a hash keyed by pid' do
      expect(Bluepill::System).to receive(:`).with('ps -Ao pid,ppid,pcpu,rss,etime,args').once.and_return(output)
      expected = {
        0 => %w[PID PPID %CPU RSS ELAPSED ARGS],
        1 => ['1', '0', '0.0', '1234', '10-01:02:03', '/sbin/init'],
        321 => ['321', '1', '12.5', '56789', '01:02', 'ruby -e "sleep 1"'],
      }
      expect(Bluepill::System.ps_axu).to eq(expected)
      expect(Bluepill::System.ps_axu).to eq(expected)
    end

    it 'should only run ps once when called from several threads at once' do
      expect(Bluepill::System).to receive(:`).once do
        sleep 0.05
        output
      end
      threads = Array.new(5) { Thread.new { Bluepill::System.ps_axu } }
      expect(threads.collect(&:value).uniq.size).to eq(1)
    end

    it 'should raise a PsError and not retry until the next tick if ps cannot be run' do
      expect(Bluepill::System).to receive(:`).once.and_raise(Errno::ENOMEM)
      message = 'Could not run ps: Errno::ENOMEM: Cannot allocate memory'
      expect { Bluepill::System.ps_axu }.to raise_error(Bluepill::System::PsError, message)
      expect { Bluepill::System.memory_usage(1, false) }.to raise_error(Bluepill::System::PsError, message)
      Bluepill::System.reset_data
      expect(Bluepill::System).to receive(:`).and_return(output)
      expect(Bluepill::System.memory_usage(1, false)).to eq(1234.0)
    end
  end

  describe :parse_etime do
    it 'should parse etime format' do
      expect(Bluepill::System.parse_elapsed_time('400-00:04:01')).to be_equal(34_560_241)
      expect(Bluepill::System.parse_elapsed_time('02:04:02')).to be_equal(7442)
      expect(Bluepill::System.parse_elapsed_time('20:03')).to be_equal(1203)
      expect(Bluepill::System.parse_elapsed_time('invalid')).to be_equal(0)
    end

    it 'should parse fields with a leading zero as decimal' do
      expect(Bluepill::System.parse_elapsed_time('08-09:08:09')).to be_equal(724_089)
    end
  end

  describe :drop_privileges do
    let(:home) { ENV['HOME'] }

    before(:each) do
      allow(Process).to receive(:groups=)
      allow(Process::Sys).to receive(:setgid)
      allow(Process::Sys).to receive(:setuid)
      allow(ENV).to receive(:[]=)
    end

    it 'should do nothing unless running as root' do
      allow(Process::Sys).to receive(:geteuid).and_return(501)
      expect(Etc).not_to receive(:getpwnam)
      Bluepill::System.drop_privileges('user', 'group', ['extra'])
      expect(Process::Sys).not_to have_received(:setuid)
    end

    context 'as root' do
      before(:each) do
        allow(Process::Sys).to receive(:geteuid).and_return(0)
      end

      it 'should do nothing without a uid, gid or supplementary groups' do
        Bluepill::System.drop_privileges(nil, nil, nil)
        expect(Process).not_to have_received(:groups=)
        expect(Process::Sys).not_to have_received(:setgid)
        expect(Process::Sys).not_to have_received(:setuid)
        expect(ENV).not_to have_received(:[]=)
      end

      it 'should switch the uid, gid, groups and home directory' do
        allow(Etc).to receive(:getpwnam).with('user').and_return(double(uid: 501))
        allow(Etc).to receive(:getgrnam).with('group').and_return(double(gid: 20))
        allow(Etc).to receive(:getgrnam).with('extra').and_return(double(gid: 30))
        allow(Etc).to receive(:getpwuid).with(501).and_return(double(dir: '/home/user'))
        allow(Process).to receive(:groups).and_return([20])
        Bluepill::System.drop_privileges('user', 'group', ['extra'])
        expect(Process).to have_received(:groups=).with([20])
        expect(Process).to have_received(:groups=).with([20, 30])
        expect(Process::Sys).to have_received(:setgid).with(20)
        expect(Process::Sys).to have_received(:setuid).with(501)
        expect(ENV).to have_received(:[]=).with('HOME', '/home/user')
      end

      it 'should keep the home directory if the user has none' do
        allow(Etc).to receive(:getpwnam).with('user').and_return(double(uid: 501))
        allow(Etc).to receive(:getpwuid).with(501).and_return(nil)
        Bluepill::System.drop_privileges('user', nil, [])
        expect(Process).not_to have_received(:groups=)
        expect(Process::Sys).not_to have_received(:setgid)
        expect(Process::Sys).to have_received(:setuid).with(501)
        expect(ENV).to have_received(:[]=).with('HOME', home)
      end

      it 'should leave HOME unset if neither the user nor the environment has one' do
        allow(Etc).to receive(:getpwnam).with('user').and_return(double(uid: 501))
        allow(Etc).to receive(:getpwuid).with(501).and_return(nil)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('HOME').and_return(nil)
        Bluepill::System.drop_privileges('user', nil, [])
        expect(ENV).to have_received(:[]=).with('HOME', nil)
      end
    end
  end

  describe :can_write_pid_file do
    let(:logger) { double('logger') }

    it 'should be true if the pid file can be written' do
      Dir.mktmpdir do |dir|
        pid_file = File.join(dir, 'test.pid')
        expect(Bluepill::System.can_write_pid_file(pid_file, logger)).to be true
        expect(File.exist?(pid_file)).to be false
      end
    end

    it 'should log the error and be false if the pid file cannot be written' do
      Dir.mktmpdir do |dir|
        pid_file = File.join(dir, 'missing', 'test.pid')
        message = begin
          FileUtils.touch(pid_file)
        rescue Errno::ENOENT => e
          "Errno::ENOENT - #{e.message}"
        end
        expect(logger).to receive(:warning).with(message)
        expect(logger).to receive(:warning).at_least(:once).with(kind_of(String))
        expect(Bluepill::System.can_write_pid_file(pid_file, logger)).to be false
      end
    end
  end

  describe :redirect_io do
    before(:each) do
      allow($stdin).to receive(:reopen)
      allow($stdout).to receive(:reopen)
      allow($stderr).to receive(:reopen)
    end

    it 'should not redirect anything without paths' do
      Bluepill::System.redirect_io(nil, nil, nil)
      expect($stdin).not_to have_received(:reopen)
      expect($stdout).not_to have_received(:reopen)
      expect($stderr).not_to have_received(:reopen)
    end

    it 'should redirect stdout and stderr to the same file' do
      Bluepill::System.redirect_io('in', 'out.log', 'out.log')
      expect($stdin).to have_received(:reopen).with('in')
      expect($stdout).to have_received(:reopen).with('out.log', 'a')
      expect($stderr).to have_received(:reopen).with($stdout)
    end

    it 'should redirect stdout and stderr to different files' do
      Bluepill::System.redirect_io(nil, 'out.log', 'err.log')
      expect($stdout).to have_received(:reopen).with('out.log', 'a')
      expect($stderr).to have_received(:reopen).with('err.log', 'a')
    end

    it 'should redirect only stderr' do
      Bluepill::System.redirect_io(nil, nil, 'err.log')
      expect($stdout).not_to have_received(:reopen)
      expect($stderr).to have_received(:reopen).with('err.log', 'a')
    end
  end
end
