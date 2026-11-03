# frozen_string_literal: true

require "tmpdir"

describe Bluepill::System::CommandPrivileges do
  let(:privileges) { Bluepill::System }
  let(:user) { Struct.new(:name, :uid, :gid, :dir).new("deploy", 1000, 1000, "/home/deploy") }
  let(:group) { Struct.new(:name, :gid, :mem) }
  let(:groups) do
    [group.new("deploy", 1000, []), group.new("web", 60, %w[deploy other]), group.new("ops", 70, %w[other])]
  end
  let(:gids) { {"deploy" => 1000, "daemon" => 1, "web" => 60, "rvm" => 50} }

  before do
    allow(Etc).to receive(:getpwnam).with("deploy").and_return(user)
    allow(Etc).to(receive(:getgrnam)) { |name| group.new(name, gids.fetch(name), []) }
    allow(Etc).to(receive(:group)) { |&block| groups.each(&block) }
    allow(Process).to receive(:groups).and_return([0, 5])
  end

  def opts(**options) = Bluepill::System::CommandOptions.new(**options)

  # Make bluepill run as root, or as another user
  def as_root(root = true) = allow(Process::Sys).to receive(:geteuid).and_return(root ? 0 : 501)

  describe ".switches_user?" do
    it "is false when bluepill doesn't run as root, which never switches" do
      as_root(false)
      expect(privileges.switches_user?(opts(uid: "deploy"))).to be(false)
    end

    {uid: "deploy", gid: "daemon", supplementary_groups: ["rvm"]}.each do |name, value|
      it "is true as root for a #{name}" do
        as_root
        expect(privileges.switches_user?(opts(name => value))).to be(true)
      end
    end

    it "is false as root without a user or groups" do
      as_root
      expect(privileges.switches_user?(opts(working_dir: "/srv"))).to be(false)
    end

    it "is false as root with no supplementary groups" do
      as_root
      expect(privileges.switches_user?(opts(supplementary_groups: []))).to be(false)
    end
  end

  describe ".setpriv?" do
    before { allow(File).to receive(:executable?).and_return(false) }

    # Find setpriv on a PATH of the directories, with it in the one given
    def setpriv_in?(path, found)
      allow(File).to receive(:executable?).with("#{found}/setpriv").and_return(true) if found
      ENV["PATH"] = path
      privileges.setpriv?
    end

    around do |example|
      path = ENV.fetch("PATH", nil)
      example.run
    ensure
      ENV["PATH"] = path
    end

    it "is true when a directory on the PATH has it" do
      expect(setpriv_in?("/bin:/usr/bin", "/usr/bin")).to be(true)
    end

    it "is false when none has it" do
      expect(setpriv_in?("/bin:/usr/bin", nil)).to be(false)
    end

    it "is false without a PATH" do
      ENV.delete("PATH")
      expect(privileges.setpriv?).to be(false)
    end
  end

  describe ".switched_command" do
    before { allow(privileges).to receive(:setpriv_options).and_return(["--groups=1"]) }

    def script = described_class::SWITCHED_SCRIPT

    it "runs the script and the command under setpriv, with the directory and files" do
      words = privileges.switched_command(opts, %w[run -x], dir: "/srv", files: ["in", nil, "err"])
      expect(words).to eq(
        ["setpriv", "--groups=1", "--", "/bin/sh", "-c", script, "bluepill", "/srv", "in", "", "err", "run", "-x"]
      )
    end

    it "gives the script an empty directory without one" do
      words = privileges.switched_command(opts, %w[run], dir: nil, files: [nil, nil, nil])
      expect(words.drop(6)).to eq(["bluepill", "", "", "", "", "run"])
    end

    it "gives setpriv the command's options" do
      options = opts(uid: "deploy")
      privileges.switched_command(options, %w[run], dir: nil, files: [nil, nil, nil])
      expect(privileges).to have_received(:setpriv_options).with(options)
    end
  end

  describe ".switched_can_write?" do
    # The options of the command to check for
    def options = @options ||= opts(uid: "deploy")

    before { allow(privileges).to receive(:setpriv_options).with(options).and_return(["--groups=1"]) }

    def can_write?(answer)
      check = described_class::WRITE_CHECK
      args = ["setpriv", "--groups=1", "--", "/bin/sh", "-c", check, "bluepill", "/run/app.pid"]
      allow(Kernel).to receive(:system).with(*args).and_return(answer)
      privileges.switched_can_write?("/run/app.pid", options)
    end

    it "is true when the check, run as the user, writes the file" do
      expect(can_write?(true)).to be(true)
    end

    it "is false when it can't" do
      expect(can_write?(false)).to be(false)
    end
  end

  describe ".setpriv_options" do
    def setpriv_options(**options) = privileges.setpriv_options(opts(**options))

    it "switches to a user, its own group, and every group it's in" do
      expect(setpriv_options(uid: "deploy")).to eq(%w[--reuid=1000 --regid=1000 --groups=1000,60])
    end

    it "switches to a user and the named group instead of its own" do
      expect(setpriv_options(uid: "deploy", gid: "daemon")).to eq(%w[--reuid=1000 --regid=1 --groups=1,60])
    end

    it "switches only the group without a user" do
      expect(setpriv_options(gid: "daemon")).to eq(%w[--regid=1 --groups=1])
    end

    it "keeps bluepill's own groups, and adds the supplementary ones, without a user or group" do
      expect(setpriv_options(supplementary_groups: ["rvm"])).to eq(%w[--groups=0,5,50])
    end

    it "adds the supplementary groups to the user's, once each" do
      expect(setpriv_options(uid: "deploy", supplementary_groups: %w[web rvm]))
        .to eq(%w[--reuid=1000 --regid=1000 --groups=1000,60,50])
    end
  end

  describe ".supplementary_gids" do
    it "is the group and the user's groups, with a user" do
      expect(privileges.supplementary_gids(user, 1000, nil)).to eq([1000, 60])
    end

    it "is only the group without a user" do
      expect(privileges.supplementary_gids(nil, 1, nil)).to eq([1])
    end

    it "is bluepill's own groups without a user or a group" do
      expect(privileges.supplementary_gids(nil, nil, nil)).to eq([0, 5])
    end

    it "adds the supplementary groups, once each" do
      expect(privileges.supplementary_gids(nil, 1, %w[rvm daemon])).to eq([1, 50])
    end

    it "leaves out a group it doesn't have" do
      expect(privileges.supplementary_gids(user, nil, [])).to eq([60])
    end
  end

  describe ".switched_environment" do
    it "sets HOME to the user's home directory, as root" do
      as_root
      expect(privileges.switched_environment(opts(uid: "deploy"))).to eq("HOME" => "/home/deploy")
    end

    it "sets nothing without a user" do
      as_root
      expect(privileges.switched_environment(opts(gid: "daemon"))).to eq({})
    end

    it "sets nothing when bluepill doesn't run as root" do
      as_root(false)
      expect(privileges.switched_environment(opts(uid: "deploy"))).to eq({})
    end

    it "sets nothing for a user without a home directory" do
      as_root
      user.dir = nil
      expect(privileges.switched_environment(opts(uid: "deploy"))).to eq({})
    end
  end

  describe ".chown_to_switched" do
    before { allow(File).to receive(:chown) }

    it "leaves a file alone when bluepill doesn't switch" do
      as_root(false)
      privileges.chown_to_switched("/run/app.pid", opts(uid: "deploy"))
      expect(File).not_to have_received(:chown)
    end

    it "gives the file to the user and its group" do
      as_root
      privileges.chown_to_switched("/run/app.pid", opts(uid: "deploy"))
      expect(File).to have_received(:chown).with(1000, 1000, "/run/app.pid")
    end

    it "gives the file the named group" do
      as_root
      privileges.chown_to_switched("/run/app.pid", opts(uid: "deploy", gid: "daemon"))
      expect(File).to have_received(:chown).with(1000, 1, "/run/app.pid")
    end

    it "changes only the group without a user" do
      as_root
      privileges.chown_to_switched("/run/app.pid", opts(gid: "daemon"))
      expect(File).to have_received(:chown).with(nil, 1, "/run/app.pid")
    end
  end

  describe "SWITCHED_SCRIPT" do
    # A temporary directory for the example, removed after it
    def dir = @dir ||= File.realpath(Dir.mktmpdir)

    after { FileUtils.remove_entry(dir) }

    def path(name) = File.join(dir, name)

    # Run the script in /bin/sh, with the directory, the files and the
    # command, and return its exit status
    def run_script(directory, files, *command)
      args = ["/bin/sh", "-c", described_class::SWITCHED_SCRIPT, "bluepill", directory, *files, *command]
      Process.wait(Kernel.spawn(*args, in: File::NULL, out: path("spawn.out"), err: path("spawn.err")))
      $?.exitstatus
    end

    it "changes to the directory" do
      run_script(dir, ["", path("out"), ""], "pwd")
      expect(File.read(path("out"))).to eq("#{dir}\n")
    end

    it "reads standard input from its file" do
      File.write(path("in"), "hello\n")
      run_script("", [path("in"), path("out"), ""], "cat")
      expect(File.read(path("out"))).to eq("hello\n")
    end

    it "appends standard output and standard error to their files" do
      File.write(path("out"), "old\n")
      run_script("", ["", path("out"), path("err")], "sh", "-c", "echo out; echo err >&2")
      expect([File.read(path("out")), File.read(path("err"))]).to eq(["old\nout\n", "err\n"])
    end

    it "puts standard error in standard output's file when they name the same one" do
      run_script("", ["", path("log"), path("log")], "sh", "-c", "echo out; echo err >&2")
      expect(File.read(path("log"))).to eq("out\nerr\n")
    end

    it "leaves a stream alone without a file for it" do
      run_script("", ["", "", ""], "sh", "-c", "echo out; echo err >&2")
      expect([File.read(path("spawn.out")), File.read(path("spawn.err"))]).to eq(["out\n", "err\n"])
    end

    it "exits with 1, without running the command, when it can't change to the directory" do
      expect(run_script(path("missing"), ["", path("out"), ""], "pwd")).to eq(1)
    end

    it "replaces itself with the command, which keeps its pid" do
      script = ["/bin/sh", "-c", described_class::SWITCHED_SCRIPT, "bluepill", "", "", path("out"), ""]
      pid = Kernel.spawn(*script, "sh", "-c", "echo $$")
      Process.wait(pid)
      expect(File.read(path("out"))).to eq("#{pid}\n")
    end
  end

  describe "WRITE_CHECK" do
    # A temporary directory for the example, removed after it
    def dir = @dir ||= File.realpath(Dir.mktmpdir)

    after do
      FileUtils.chmod(0o700, dir)
      FileUtils.remove_entry(dir)
    end

    def writes?(file) = Kernel.system("/bin/sh", "-c", described_class::WRITE_CHECK, "bluepill", file)

    it "passes for a file it can create, and removes it" do
      file = File.join(dir, "app.pid")
      expect([writes?(file), File.exist?(file)]).to eq([true, false])
    end

    it "fails for a file in a directory it can't write" do
      FileUtils.chmod(0o500, dir)
      expect(writes?(File.join(dir, "app.pid"))).to be(false)
    end
  end
end
