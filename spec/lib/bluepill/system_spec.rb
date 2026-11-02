require "tmpdir"

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
      1 => ["1", "0", "1.5", "100", "01:00", "init"],
      2 => ["2", "1", "2.5", "200", "02:00", "child one"],
      3 => ["3", "2", "3.5", "300", "03:00", "grandchild"],
      4 => ["4", "1", "4.5", "400", "04:00", "child two"]
    }
  end

  describe ".pid_alive?" do
    it "sends the process the zero signal, once" do
      allow(Process).to receive(:kill).and_return(1)
      described_class.pid_alive?(555)
      expect(Process).to have_received(:kill).with(0, 555).once
    end

    it "is true if process responds to zero signal" do
      allow(Process).to receive(:kill).with(0, 555).and_return(1)
      expect(described_class.pid_alive?(555)).to be true
    end

    it "is false if process throws exception on zero signal" do
      allow(Process).to receive(:kill).with(0, 555).and_raise(Errno::ESRCH)
      expect(described_class.pid_alive?(555)).to be false
    end

    it "is true if there is no permission to signal the process" do
      allow(Process).to receive(:kill).with(0, 555).and_raise(Errno::EPERM)
      expect(described_class.pid_alive?(555)).to be true
    end

    it "is false if signaling raises any other error" do
      allow(Process).to receive(:kill).with(0, nil).and_raise(TypeError)
      expect(described_class.pid_alive?(nil)).to be false
    end
  end

  describe ".started_at" do
    before { allow(Time).to receive(:now).and_return(Time.at(1_000_000)) }

    # Make ps print an elapsed time for pid 555
    def ps_prints(elapsed)
      allow(IO).to receive(:popen).with(%w[ps -o etime= -p 555], err: File::NULL).and_return(elapsed)
    end

    it "asks ps once" do
      ps_prints("  1-02:03:04\n")
      described_class.started_at(555)
      expect(IO).to have_received(:popen).once
    end

    it "subtracts the process's elapsed time from now" do
      ps_prints("  1-02:03:04\n")
      expect(described_class.started_at(555)).to eq 1_000_000 - 93_784
    end

    it "is nil without such a process" do
      ps_prints("")
      expect(described_class.started_at(555)).to be_nil
    end

    it "is nil when ps prints only a newline" do
      ps_prints("\n")
      expect(described_class.started_at(555)).to be_nil
    end

    it "is nil if ps can't run" do
      allow(IO).to receive(:popen).and_raise(Errno::ENOENT)
      expect(described_class.started_at(555)).to be_nil
    end

    it "only passes ps a pid" do
      expect { described_class.started_at("1; rm -rf /") }.to raise_error(ArgumentError)
    end

    context "with a real process" do
      let(:pid) { ::Process.spawn("sleep", "10") }

      after do
        ::Process.kill("KILL", pid)
        begin
          ::Process.wait(pid)
        rescue Errno::ECHILD
          nil # JRuby 1.7 reaps it already
        end
      end

      it "reads what ps prints" do
        expect(described_class.started_at(pid)).to be_within(2).of(Integer(Time.now))
      end
    end
  end

  describe ".boot_time" do
    before do
      allow(described_class).to receive(:started_at).with(1).and_return(42)
    end

    it "is when pid 1 started" do
      expect(described_class.boot_time).to eq 42
    end

    it "asks once" do
      described_class.boot_time
      expect(described_class).to have_received(:started_at).once
    end
  end

  describe ".cpu_usage" do
    before { stub_ps(ps) }

    it "is nil for an unknown pid" do
      expect(described_class.cpu_usage(99, true)).to be_nil
    end

    it "returns the cpu usage of the process" do
      expect(described_class.cpu_usage(2, false)).to eq(2.5)
    end

    it "includes the cpu usage of all descendants" do
      expect(described_class.cpu_usage(1, true)).to eq(12.0)
    end

    it "skips children that are missing from ps output" do
      allow(described_class).to receive(:get_children).with(1).and_return([2, 99])
      expect(described_class.cpu_usage(1, true)).to eq(4.0)
    end
  end

  describe ".memory_usage" do
    before { stub_ps(ps) }

    it "is nil for an unknown pid" do
      expect(described_class.memory_usage(99, true)).to be_nil
    end

    it "returns the memory usage of the process" do
      expect(described_class.memory_usage(2, false)).to be_a(Float).and eq(200.0)
    end

    it "includes the memory usage of all descendants" do
      expect(described_class.memory_usage(1, true)).to be_a(Float).and eq(1000.0)
    end

    it "skips children that are missing from ps output" do
      allow(described_class).to receive(:get_children).with(1).and_return([2, 99])
      expect(described_class.memory_usage(1, true)).to be_a(Float).and eq(300.0)
    end

    it "parses the memory usage of children as floats" do
      stub_ps(1 => ps[1], 2 => ["2", "1", "2.5", "200.5", "02:00", "child one"])
      expect(described_class.memory_usage(1, true)).to be_a(Float).and eq(300.5)
    end
  end

  describe ".running_time" do
    before { stub_ps(ps) }

    it "is nil for an unknown pid" do
      expect(described_class.running_time(99)).to be_nil
    end

    it "returns the elapsed time in seconds" do
      expect(described_class.running_time(3)).to eq(180)
    end
  end

  describe ".command" do
    before { stub_ps(ps) }

    it "is nil for an unknown pid" do
      expect(described_class.command(99)).to be_nil
    end

    it "returns the command of the process" do
      expect(described_class.command(2)).to eq("child one")
    end
  end

  describe ".get_children" do
    before { stub_ps(ps) }

    it "returns all descendants" do
      expect(described_class.get_children(1)).to eq([2, 4, 3])
    end

    it "returns an empty array for a process without children" do
      expect(described_class.get_children(3)).to eq([])
    end

    it "shares one empty array for every process without children" do
      expect(described_class.get_children(3)).to be(described_class::NO_PIDS)
    end

    it "returns an empty array for a pid that is not an Integer" do
      expect(described_class.get_children("1")).to eq([])
    end

    it "reads the ps table once, however many processes it looks in" do
      [1, 2, 3].each { |pid| described_class.get_children(pid) }
      expect(described_class).to have_received(:ps_axu).once
    end

    it "returns the same descendants every time" do
      2.times { described_class.get_children(1) }
      expect(described_class.get_children(1)).to eq([2, 4, 3])
    end

    it "reads the ps table again after the data is reset" do
      described_class.get_children(1)
      described_class.reset_data
      stub_ps(ps.merge(5 => ["5", "1", "0.0", "50", "00:01", "child three"]))
      expect(described_class.get_children(1)).to eq([2, 4, 5, 3])
    end

    it "returns an empty array if ps could not be run" do
      allow(described_class).to receive(:ps_axu).and_raise(Bluepill::System::PsError)
      expect(described_class.get_children(1)).to eq([])
    end

    context "when ps output includes its header row" do
      # "PID".to_i and "PPID".to_i are both 0
      let(:ps) { super().merge(0 => %w[PID PPID %CPU RSS ELAPSED COMMAND]) }

      it "returns an empty array for a nil pid" do
        expect(described_class.get_children(nil)).to eq([])
      end

      it "returns an empty array for pid 0" do
        expect(described_class.get_children(0)).to eq([])
      end

      it "still returns all descendants of a real pid" do
        expect(described_class.get_children(1)).to eq([2, 4, 3])
      end
    end
  end

  describe ".delete_if_exists" do
    it "does nothing for a nil filename" do
      allow(File).to receive(:unlink)
      described_class.delete_if_exists(nil)
      expect(File).not_to have_received(:unlink)
    end

    context "when the file does not exist" do
      before do
        allow(File).to receive(:exist?).with("missing").and_return(false)
        allow(File).to receive(:unlink)
        described_class.delete_if_exists("missing")
      end

      it "checks once" do
        expect(File).to have_received(:exist?).once
      end

      it "does nothing" do
        expect(File).not_to have_received(:unlink)
      end
    end

    context "when the file exists" do
      let(:dir) { Dir.mktmpdir }

      after do
        FileUtils.remove_entry(dir)
      end

      it "deletes it" do
        filename = File.join(dir, "file")
        File.write(filename, "x")
        described_class.delete_if_exists(filename)
        expect(File.exist?(filename)).to be false
      end
    end

    context "when the file disappears before deletion" do
      before do
        allow(File).to receive(:exist?).with("file").and_return(true)
        allow(File).to receive(:unlink).with("file").and_raise(Errno::ENOENT)
      end

      it "ignores it" do
        expect { described_class.delete_if_exists("file") }.not_to raise_error
      end

      it "tries to delete it once" do
        described_class.delete_if_exists("file")
        expect(File).to have_received(:unlink).once
      end
    end

    context "when permission is denied" do
      before do
        allow(File).to receive(:exist?).with("file").and_return(true)
        allow(File).to receive(:unlink).with("file").and_raise(Errno::EACCES)
        allow($stderr).to receive(:puts)
        described_class.delete_if_exists("file")
      end

      it "tries 3 times" do
        expect(File).to have_received(:unlink).exactly(3).times
      end

      it "then warns" do
        expect($stderr).to have_received(:puts).with("Warning: permission denied trying to delete file").once
      end
    end
  end

  describe ".store" do
    it "is Hash" do
      expect(described_class.store).to be_a(Hash)
    end

    it "returns the same Hash on every call" do
      expect(described_class.store).to equal(described_class.store)
    end

    it "stores assigned pairs" do
      described_class.store[:somekey] = 10
      expect(described_class.store[:somekey]).to be(10)
    end
  end

  describe ".children_by_parent" do
    it "indexes each process's children by its pid, in ps's order" do
      stub_ps(ps)
      expect(described_class.children_by_parent).to eq(0 => [1], 1 => [2, 4], 2 => [3])
    end
  end

  describe ".reset_data" do
    it "clears the #store" do
      described_class.store[:anotherkey] = "Lorem ipsum dolor sit amet."
      described_class.reset_data
      expect(described_class.store).to be_empty
    end

    it "forgets the children index" do
      stub_ps(ps)
      described_class.children_by_parent
      described_class.reset_data
      stub_ps({})
      expect(described_class.children_by_parent).to eq({})
    end

    it "leaves an empty #store empty" do
      described_class.reset_data
      expect(described_class.store).to be_empty
    end
  end

  describe ".ps_axu" do
    let(:output) do
      [
        "  PID  PPID  %CPU    RSS     ELAPSED ARGS",
        "    1     0   0.0   1234 10-01:02:03 /sbin/init",
        '  321     1  12.5  56789       01:02 ruby -e "sleep 1"',
        "  322     1   0.0      0       00:01",
        '  323     1   0.0    512       00:02 sh -c "echo  two  spaces"'
      ].join("\n")
    end

    context "when ps runs" do
      let(:table) do
        {
          0 => %w[PID PPID %CPU RSS ELAPSED ARGS],
          1 => ["1", "0", "0.0", "1234", "10-01:02:03", "/sbin/init"],
          321 => ["321", "1", "12.5", "56789", "01:02", 'ruby -e "sleep 1"'],
          322 => ["322", "1", "0.0", "0", "00:01", ""],
          323 => ["323", "1", "0.0", "512", "00:02", 'sh -c "echo  two  spaces"']
        }
      end

      before do
        allow(described_class).to receive(:`).and_return(output)
      end

      it "parses ps output into a hash keyed by pid, and keeps it until the next tick" do
        expect(Array.new(2) { described_class.ps_axu }).to eq([table, table])
      end

      it "runs ps once a tick" do
        2.times { described_class.ps_axu }
        expect(described_class).to have_received(:`).with("ps -Ao pid,ppid,pcpu,rss,etime,args").once
      end
    end

    # A pill file could set $;, which split uses when it's given no pattern
    context "when $; is set" do
      let(:table) { {0 => %w[PID PPID %CPU RSS ELAPSED ARGS], 1 => ["1", "0", "0.0", "1234", "10-01:02:03", "/sbin/init"]} }

      around do |example|
        separator = $;
        begin
          $; = ","
          example.run
        ensure
          $; = separator
        end
      end

      it "still splits ps output on whitespace" do
        allow(described_class).to receive(:`).and_return(output.lines.first(2).join)
        expect(described_class.ps_axu).to eq(table)
      end
    end

    context "when called from several threads at once" do
      before do
        allow(described_class).to receive(:`) do
          sleep 0.05
          output
        end
      end

      def ps_axu_in_threads
        Array.new(5) { Thread.new { described_class.ps_axu } }.collect(&:value)
      end

      it "gives them all the same table" do
        expect(ps_axu_in_threads.uniq.size).to eq(1)
      end

      it "only runs ps once" do
        ps_axu_in_threads
        expect(described_class).to have_received(:`).once
      end
    end

    context "when ps cannot be run" do
      before do
        allow(described_class).to receive(:`).and_raise(Errno::ENOMEM)
      end

      # Try to read ps, and carry on past the PsError
      def attempt
        yield
      rescue Bluepill::System::PsError
        nil
      end

      def message
        "Could not run ps: Errno::ENOMEM: Cannot allocate memory"
      end

      it "raises a PsError" do
        expect { described_class.ps_axu }.to raise_error(Bluepill::System::PsError, message)
      end

      it "raises it again until the next tick" do
        attempt { described_class.ps_axu }
        expect { described_class.memory_usage(1, false) }.to raise_error(Bluepill::System::PsError, message)
      end

      it "doesn't retry until the next tick" do
        2.times { attempt { described_class.ps_axu } }
        expect(described_class).to have_received(:`).once
      end

      it "retries on the next tick" do
        attempt { described_class.ps_axu }
        described_class.reset_data
        allow(described_class).to receive(:`).and_return(output)
        expect(described_class.memory_usage(1, false)).to eq(1234.0)
      end
    end
  end

  describe ".parse_etime" do
    it "parses etime format" do
      times = %w[400-00:04:01 02:04:02 20:03 invalid].collect { |time| described_class.parse_elapsed_time(time) }
      expect(times).to eql [34_560_241, 7442, 1203, 0]
    end

    it "parses fields with a leading zero as decimal" do
      expect(described_class.parse_elapsed_time("08-09:08:09")).to equal(724_089)
    end
  end

  describe ".drop_privileges" do
    # What it changed about the process, in order
    let(:calls) { [] }

    before do
      allow(Process).to(receive(:groups=)) { |groups| calls << [:groups=, groups] }
      allow(Process).to(receive(:initgroups)) { |*args| calls << [:initgroups, *args] }
      allow(Process::Sys).to(receive(:setgid)) { |gid| calls << [:setgid, gid] }
      allow(Process::Sys).to(receive(:setuid)) { |uid| calls << [:setuid, uid] }
      allow(ENV).to(receive(:[]=)) { |*args| calls << [:[]=, *args] }
    end

    context "when not running as root" do
      before do
        allow(Process::Sys).to receive(:geteuid).and_return(501)
        allow(Etc).to receive(:getpwnam)
        described_class.drop_privileges("user", "group", ["extra"])
      end

      it "doesn't look up the user" do
        expect(Etc).not_to have_received(:getpwnam)
      end

      it "changes nothing" do
        expect(calls).to eq []
      end
    end

    context "when running as root" do
      before do
        allow(Process::Sys).to receive(:geteuid).and_return(0)
        allow(Etc).to receive(:getgrnam).with("group").and_return(instance_double(Etc::Group, gid: 20))
        allow(Etc).to receive(:getgrnam).with("extra").and_return(instance_double(Etc::Group, gid: 30))
      end

      # Make the user exist, with a home directory
      def user(dir = "/home/user")
        allow(Etc).to receive(:getpwnam).with("user").and_return(instance_double(Etc::Passwd, name: "user", uid: 501, gid: 10, dir: dir))
      end

      it "does nothing without a uid, gid or supplementary groups" do
        described_class.drop_privileges(nil, nil, nil)
        expect(calls).to eq []
      end

      it "gives a user the user's own groups, the gid, and the supplementary groups" do
        user
        allow(Process).to receive(:groups).and_return([10, 20])
        described_class.drop_privileges("user", "group", ["extra"])
        expect(calls).to eq [[:initgroups, "user", 20], [:groups=, [10, 20, 30]], [:setgid, 20], [:setuid, 501], [:[]=, "HOME", "/home/user"]]
      end

      it "gives a user without a gid the user's primary group" do
        user
        described_class.drop_privileges("user", nil, [])
        expect(calls).to eq [[:initgroups, "user", 10], [:setgid, 10], [:setuid, 501], [:[]=, "HOME", "/home/user"]]
      end

      it "keeps the home directory if the user has none" do
        user(nil)
        described_class.drop_privileges("user", nil, [])
        expect(calls).to eq [[:initgroups, "user", 10], [:setgid, 10], [:setuid, 501]]
      end

      it "uses only the gid and supplementary groups without a uid" do
        allow(Process).to receive(:groups).and_return([20])
        described_class.drop_privileges(nil, "group", ["extra"])
        expect(calls).to eq [[:groups=, [20]], [:groups=, [20, 30]], [:setgid, 20]]
      end

      it "adds supplementary groups to bluepill's own without a uid or gid" do
        allow(Process).to receive(:groups).and_return([0])
        described_class.drop_privileges(nil, nil, ["extra"])
        expect(calls).to eq [[:groups=, [0, 30]]]
      end
    end
  end

  describe ".can_write_pid_file" do
    let(:logger) { instance_double(Bluepill::Logger) }
    let(:dir) { Dir.mktmpdir }

    after do
      FileUtils.remove_entry(dir)
    end

    context "when the pid file can be written" do
      it "is true" do
        expect(described_class.can_write_pid_file(File.join(dir, "test.pid"), logger)).to be true
      end

      it "leaves no pid file" do
        described_class.can_write_pid_file(File.join(dir, "test.pid"), logger)
        expect(File.exist?(File.join(dir, "test.pid"))).to be false
      end
    end

    context "when the pid file cannot be written" do
      let(:pid_file) { File.join(dir, "missing", "test.pid") }
      let(:warnings) { [] }

      before do
        allow(logger).to(receive(:warning)) { |message| warnings << message }
      end

      it "is false" do
        expect(described_class.can_write_pid_file(pid_file, logger)).to be false
      end

      # What writing the pid file raises, as it's logged
      def error
        FileUtils.touch(pid_file)
      rescue Errno::ENOENT => e
        "Errno::ENOENT - #{e.message}"
      end

      it "logs the error" do
        described_class.can_write_pid_file(pid_file, logger)
        expect(warnings.first).to eq error
      end

      it "logs its backtrace after it" do
        described_class.can_write_pid_file(pid_file, logger)
        expect(warnings.drop(1)).to all(be_a(String)).and(be_any)
      end
    end
  end

  describe ".redirect_io" do
    # What each stream was reopened with, in order
    let(:reopened) { [] }

    before do
      allow($stdin).to(receive(:reopen)) { |*args| reopened << [:stdin, *args] }
      allow($stdout).to(receive(:reopen)) { |*args| reopened << [:stdout, *args] }
      allow($stderr).to(receive(:reopen)) { |*args| reopened << [:stderr, *args] }
    end

    it "does not redirect anything without paths" do
      described_class.redirect_io(nil, nil, nil)
      expect(reopened).to eq []
    end

    it "redirects stdout and stderr to the same file" do
      described_class.redirect_io("in", "out.log", "out.log")
      expect(reopened).to eq [[:stdin, "in"], [:stdout, "out.log", "a"], [:stderr, $stdout]]
    end

    it "redirects stdout and stderr to different files" do
      described_class.redirect_io(nil, "out.log", "err.log")
      expect(reopened).to eq [[:stdout, "out.log", "a"], [:stderr, "err.log", "a"]]
    end

    it "redirects only stderr" do
      described_class.redirect_io(nil, nil, "err.log")
      expect(reopened).to eq [[:stderr, "err.log", "a"]]
    end
  end
end
