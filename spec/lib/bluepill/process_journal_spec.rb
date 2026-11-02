# frozen_string_literal: true

require "tmpdir"

describe Bluepill::ProcessJournal do
  let(:log) { [] }
  let(:logger) do
    instance_double(Bluepill::Logger).tap do |logger|
      allow(logger).to(receive(:debug)) { |message| log << [:debug, message] }
      allow(logger).to(receive(:info)) { |message| log << [:info, message] }
    end
  end
  # The journal directory before 0.2
  let(:legacy_dir) { Dir.mktmpdir }

  around do |example|
    old_logger = described_class.instance_variable_get(:@logger)
    old_base_dir = described_class.instance_variable_get(:@journal_base_dir)
    old_legacy_dir = described_class.instance_variable_get(:@legacy_journal_dir)
    begin
      example.run
    ensure
      described_class.instance_variable_set(:@logger, old_logger)
      described_class.instance_variable_set(:@journal_base_dir, old_base_dir)
      described_class.instance_variable_set(:@legacy_journal_dir, old_legacy_dir)
    end
  end

  before do
    Dir.mkdir(dir)
    described_class.instance_variable_set(:@logger, logger)
    described_class.instance_variable_set(:@journal_base_dir, dir)
    described_class.instance_variable_set(:@legacy_journal_dir, legacy_dir)
    allow(described_class).to receive(:sleep)
    allow(::Process).to receive(:kill)
    # Ids without a start time, journaled since the machine booted
    allow(Bluepill::System).to receive_messages(pid_alive?: false, started_at: nil, boot_time: 0)
  end

  after do
    FileUtils.remove_entry(legacy_dir)
  end

  # The app's journal directory, in the one before 0.2
  def dir = File.join(legacy_dir, "app")

  def write_journal(filename, ids) = File.open(filename, "w") { |f| ids.each { |id| f.puts(id) } }

  def lock_log(filename)
    [[:debug, "Acquired lock #{filename}.lock"], [:debug, "Cleared lock #{filename}.lock"]]
  end

  # Return each file's permissions
  def modes(*files) = files.collect { |file| File.stat(file).mode & 0o777 }

  describe ".logger=" do
    it "only sets the logger once" do
      described_class.instance_variable_set(:@logger, nil)
      described_class.logger = logger
      described_class.logger = instance_double(Bluepill::Logger)
      expect(described_class.logger).to eq logger
    end
  end

  describe ".setup" do
    before do
      described_class.instance_variable_set(:@journal_base_dir, nil)
      described_class.instance_variable_set(:@legacy_journal_dir, nil)
    end

    def journals = File.join(dir, "journals")

    def journal_dirs = [described_class.journal_base_dir, described_class.legacy_journal_dir]

    context "when first set up" do
      before do
        described_class.setup(dir, :web)
      end

      it "sets the app's journal directory, in the one before 0.2" do
        expect(journal_dirs).to eq [File.join(journals, "web"), journals]
      end

      it "creates them, writable by everyone" do
        made = journal_dirs.collect { |journal_dir| File.directory?(journal_dir) && modes(journal_dir) }
        expect(made).to eq [[0o777], [0o777]]
      end

      it "keeps them when set up again" do
        described_class.setup(File.join(dir, "other"), :api)
        expect(journal_dirs).to eq [File.join(journals, "web"), journals]
      end

      it "creates no others when set up again" do
        described_class.setup(File.join(dir, "other"), :api)
        expect([File.join(dir, "other"), File.join(journals, "api")].select { |path| File.exist?(path) }).to be_empty
      end
    end

    it "only makes the journal directories writable if they exist" do
      Dir.mkdir(journals, 0o700)
      Dir.mkdir(File.join(journals, "web"), 0o700)
      described_class.setup(dir, "web")
      expect(modes(journals, File.join(journals, "web"))).to eq [0o777, 0o777]
    end
  end

  describe ".journal_dirs" do
    it "lists the app's journal directory, then the one before 0.2" do
      expect(described_class.journal_dirs).to eq [dir, legacy_dir]
    end
  end

  describe ".skip_id?" do
    it "skips non-integers and ids <= 1" do
      ids = [nil, "5", -5, 0, 1, 2]
      expect(ids.collect { |id| described_class.skip_id?(id) }).to eq [true, true, true, true, true, false]
    end

    # An Integer that isn't an instance of Integer. Every Integer is one
    # since Ruby 2.4, so this keeps is_a? from passing as instance_of?.
    it "accepts instances of Integer subclasses" do
      id = instance_double(Integer)
      allow(id).to receive(:is_a?).with(Integer).and_return(true)
      allow(id).to receive(:<=).with(1).and_return(false)
      expect(described_class.skip_id?(id)).to be false
    end
  end

  describe ".for" do
    it "is a process's journal" do
      journal = described_class.for("web")
      expect([journal.class, journal.name]).to eq [described_class::Journal, "web"]
    end
  end

  describe ".acquire_atomic_fs_lock" do
    let(:name) { File.join(dir, "journal") }

    around do |example|
      old_umask = File.umask(0o022)
      begin
        example.run
      ensure
        File.umask(old_umask)
      end
    end

    it "returns what the block returns" do
      expect(described_class.acquire_atomic_fs_lock(name) { :result }).to eq :result
    end

    it "holds a private lock directory while yielding" do
      held = described_class.acquire_atomic_fs_lock(name) { File.directory?("#{name}.lock") && modes("#{name}.lock") }
      expect(held).to eq [0o700]
    end

    it "removes the lock afterwards" do
      described_class.acquire_atomic_fs_lock(name) { nil }
      expect(File.exist?("#{name}.lock")).to be false
    end

    it "logs acquiring and clearing the lock" do
      described_class.acquire_atomic_fs_lock(name) { nil }
      expect(log).to eq lock_log(name)
    end

    context "when another process holds the lock for a second" do
      before do
        Dir.mkdir("#{name}.lock")
        allow(described_class).to(receive(:sleep) { Dir.rmdir("#{name}.lock") })
      end

      it "waits a second for it" do
        described_class.acquire_atomic_fs_lock(name) { nil }
        expect(described_class).to have_received(:sleep).with(1).once
      end

      it "yields once the lock is released" do
        expect { |block| described_class.acquire_atomic_fs_lock(name, &block) }.to yield_control.once
      end

      it "leaves no lock behind" do
        described_class.acquire_atomic_fs_lock(name) { nil }
        expect(Dir.glob("#{name}*")).to be_empty
      end

      it "logs the wait" do
        described_class.acquire_atomic_fs_lock(name) { nil }
        expect(log).to eq [[:debug, "Waiting for lock #{name}.lock"]] + lock_log(name)
      end
    end

    context "when another process keeps the lock" do
      before do
        Dir.mkdir("#{name}.lock")
      end

      # Try to take the lock, and carry on past the timeout
      def acquire
        described_class.acquire_atomic_fs_lock(name) { raise "should not yield" }
      rescue described_class::LockTimeoutError
        nil
      end

      it "gives up after 10 attempts" do
        expect { described_class.acquire_atomic_fs_lock(name) { raise "should not yield" } }
          .to raise_error(described_class::LockTimeoutError, "Timeout waiting for lock #{name}.lock")
      end

      it "waits a second between attempts" do
        acquire
        expect(described_class).to have_received(:sleep).with(1).exactly(9).times
      end

      it "leaves the other lock" do
        acquire
        expect(File.directory?("#{name}.lock")).to be true
      end

      it "logs each wait, and the timeout" do
        acquire
        waits = [[:debug, "Waiting for lock #{name}.lock"]] * 9
        expect(log).to eq waits + [[:info, "Timeout waiting for lock #{name}.lock"]]
      end
    end

    context "when the block raises" do
      # Take the lock, and carry on past what the block raises
      def acquire
        described_class.acquire_atomic_fs_lock(name) { raise Errno::EEXIST }
      rescue Errno::EEXIST
        nil
      end

      it "raises it" do
        expect { described_class.acquire_atomic_fs_lock(name) { raise Errno::EEXIST } }.to raise_error(Errno::EEXIST)
      end

      it "removes the lock" do
        acquire
        expect(File.exist?("#{name}.lock")).to be false
      end

      it "logs acquiring and clearing the lock" do
        acquire
        expect(log).to eq lock_log(name)
      end
    end
  end

  describe ".clear_atomic_fs_lock" do
    context "when the lock does not exist" do
      before do
        allow(Dir).to receive(:rmdir).and_call_original
        described_class.clear_atomic_fs_lock(File.join(dir, "missing.lock"))
      end

      it "removes nothing" do
        expect(Dir).not_to have_received(:rmdir)
      end

      it "logs nothing" do
        expect(log).to eq []
      end
    end

    context "when the lock exists" do
      before do
        Dir.mkdir(File.join(dir, "journal.lock"))
        described_class.clear_atomic_fs_lock(File.join(dir, "journal.lock"))
      end

      it "removes the lock directory" do
        expect(File.exist?(File.join(dir, "journal.lock"))).to be false
      end

      it "logs it" do
        expect(log).to eq [[:debug, "Cleared lock #{File.join(dir, "journal.lock")}"]]
      end
    end
  end

  describe ".clear_all_atomic_fs_locks" do
    let(:lock) { File.join(dir, ".bluepill_pids_journal.web.lock") }
    # A file, another app's lock, and a lock before 0.2
    let(:others) do
      [
        File.join(dir, ".b.lock"),
        File.join(legacy_dir, "other", ".bluepill_pids_journal.web.lock"),
        File.join(legacy_dir, ".bluepill_pids_journal.web.lock")
      ]
    end

    before do
      file, other_lock, legacy_lock = others
      [lock, File.dirname(other_lock), other_lock, legacy_lock].each { |lock_dir| Dir.mkdir(lock_dir) }
      File.write(file, "")
      Dir.chdir(legacy_dir) { described_class.clear_all_atomic_fs_locks }
    end

    it "removes the app's lock directories" do
      expect(File.exist?(lock)).to be false
    end

    it "leaves files, other apps' locks, and locks before 0.2" do
      kinds = others.collect { |path| [File.file?(path), File.directory?(path)] }
      expect(kinds).to eq [[true, false], [false, true], [false, true]]
    end

    it "logs the locks it removes" do
      expect(log).to eq [[:debug, "Cleared lock #{lock}"]]
    end
  end

  describe described_class::Kind do
    describe "#filename" do
      it "is a pid journal's, in the directory" do
        expect(Bluepill::ProcessJournal::PID.filename("/old", :app)).to eq "/old/.bluepill_pids_journal.app"
      end

      it "is a process group journal's, in the directory" do
        expect(Bluepill::ProcessJournal::PGID.filename("/old", "app")).to eq "/old/.bluepill_pgids_journal.app"
      end
    end

    it "keeps what it's made with" do
      kind = described_class.new("id", "thing", "ids", 2)
      made = [kind.name, kind.label, kind.sign, kind.filename("/old", "app")]
      expect(made).to eq ["id", "thing", 2, "/old/.bluepill_ids_journal.app"]
    end

    it "describes pids" do
      pid = Bluepill::ProcessJournal::PID
      expect([pid.name, pid.label, pid.sign]).to eq ["pid", "process", 1]
    end

    it "describes process groups" do
      pgid = Bluepill::ProcessJournal::PGID
      expect([pgid.name, pgid.label, pgid.sign]).to eq ["pgid", "process group", -1]
    end
  end

  {"pid" => described_class::PID, "pgid" => described_class::PGID}.each do |kind, journal_kind|
    describe ".journal_ids of a #{kind} journal" do
      context "with a journal" do
        let(:filename) { File.join(dir, "j") }

        before do
          write_journal(filename, [0, 1, 42, 43])
        end

        it "reads valid ids" do
          expect(described_class.journal_ids(journal_kind, filename)).to eq [42, 43]
        end

        it "logs the file and the ids" do
          described_class.journal_ids(journal_kind, filename)
          expect(log).to eq [[:debug, "#{kind} journal file: #{filename}"], [:debug, "#{kind} journal = 42 43"]]
        end
      end

      context "without a journal" do
        let(:filename) { File.join(dir, "missing") }

        it "is empty" do
          expect(described_class.journal_ids(journal_kind, filename)).to eq []
        end

        it "logs the file" do
          described_class.journal_ids(journal_kind, filename)
          expect(log).to eq [[:debug, "#{kind} journal file: #{filename}"]]
        end
      end
    end
  end

  describe "Journal#kill_all" do
    it "kills pids, and then pgids" do
      calls = []
      allow(described_class).to(receive(:kill_all)) { |kind, name| calls << [kind, name] }
      described_class.for("app").kill_all
      expect(calls).to eq [[described_class::PID, "app"], [described_class::PGID, "app"]]
    end
  end

  {
    described_class::PID => [1, "process", "pid"],
    described_class::PGID => [-1, "process group", "pgid"]
  }.each do |journal_kind, (sign, label, kind)|
    describe ".kill_all of #{kind}s" do
      let(:filename) { journal_kind.filename(dir, "app") }
      # The signals sent and the waits, in order
      let(:calls) { [] }

      before do
        allow(::Process).to(receive(:kill)) { |*args| calls << args }
        allow(described_class).to(receive(:sleep)) { |seconds| calls << [:sleep, seconds] }
      end

      # The journal that bluepill 0.1 and earlier shared, in the directory before 0.2
      define_method(:legacy_filename) do
        journal_kind.filename(legacy_dir, "app")
      end

      define_method(:journal_log) do |ids|
        [[:debug, "#{kind} journal file: #{filename}"], [:debug, "#{kind} journal = #{ids.join(" ")}"]]
      end

      # Reading the journal that bluepill 0.1 and earlier shared, after the app's
      define_method(:no_legacy_journal_log) do
        [
          [:debug, "#{kind} journal file: #{legacy_filename}"],
          [:debug, "No previous process journal - Skipping cleanup"]
        ]
      end

      # The log of a cleanup of the app's journal that found ids, and signaled them
      define_method(:cleanup_log) do |ids, *signaled|
        journal_log(ids) + [[:debug, "Acquired lock #{filename}.lock"], *signaled] +
          [[:debug, "Journal cleanup completed"], [:debug, "Cleared lock #{filename}.lock"]] + no_legacy_journal_log
      end

      # Make an id's process exit before the signal reaches it
      define_method(:missing) do |signal, id|
        allow(::Process).to(receive(:kill).with(signal, sign * id)) do |*args|
          calls << args
          raise Errno::ESRCH
        end
      end

      context "without a journal" do
        before do
          allow(Bluepill::System).to receive(:delete_if_exists)
          described_class.kill_all(journal_kind, "app")
        end

        it "signals nothing" do
          expect(calls).to be_empty
        end

        it "deletes nothing" do
          expect(Bluepill::System).not_to have_received(:delete_if_exists)
        end

        it "skips cleanup" do
          expect(log).to eq [
            [:debug, "#{kind} journal file: #{filename}"],
            [:debug, "No previous process journal - Skipping cleanup"]
          ] + no_legacy_journal_log
        end
      end

      context "with a journal from before 0.2 too" do
        before do
          write_journal(filename, [42])
          write_journal(legacy_filename, [43])
          described_class.kill_all(journal_kind, "app")
        end

        it "terms what both list, the app's first" do
          expect(calls).to eq [["TERM", sign * 42], ["TERM", sign * 43]]
        end

        it "resets both, and leaves no lock" do
          expect([filename, legacy_filename, "#{legacy_filename}.lock"].select { |path| File.exist?(path) }).to be_empty
        end

        it "logs what it termed from the one before 0.2" do
          expect(log).to include([:info, "Termed old #{label} 43"])
        end
      end

      context "with an id that now belongs to another process" do
        before do
          File.write(filename, "42 20000\n")
          allow(Bluepill::System).to receive(:started_at).with(42).and_return(50_000)
          described_class.kill_all(journal_kind, "app")
        end

        it "leaves it alone" do
          expect(calls).to be_empty
        end

        it "resets the journal" do
          expect(File.exist?(filename)).to be false
        end

        it "logs that it skipped it" do
          expect(log).to include([:info, "Skipping old #{label} 42, which isn't the one bluepill started"])
        end
      end

      context "with another app's journal" do
        # The journal of another app's process of the same name
        define_method(:other) do
          journal_kind.filename(File.join(legacy_dir, "other"), "app")
        end

        before do
          Dir.mkdir(File.dirname(other))
          write_journal(other, [44])
          described_class.kill_all(journal_kind, "app")
        end

        it "signals nothing" do
          expect(calls).to be_empty
        end

        it "leaves it alone" do
          expect(File.read(other)).to eq "44\n"
        end
      end

      context "with ids that exit on TERM" do
        before do
          write_journal(filename, [42, 43])
          missing("TERM", 43)
          described_class.kill_all(journal_kind, "app")
        end

        it "terms each, without waiting" do
          expect(calls).to eq [["TERM", sign * 42], ["TERM", sign * 43]]
        end

        it "resets the journal, and leaves no lock" do
          expect([filename, "#{filename}.lock"].select { |path| File.exist?(path) }).to be_empty
        end

        it "logs each, under the lock" do
          expect(log).to eq cleanup_log(
            [42, 43],
            [:info, "Termed old #{label} 42"],
            [:debug, "Unable to term missing #{label} 43"]
          )
        end
      end

      context "with an id that survives TERM" do
        before do
          write_journal(filename, [42])
          allow(Bluepill::System).to receive(:pid_alive?).with(sign * 42).and_return(true)
          described_class.kill_all(journal_kind, "app")
        end

        it "terms it, waits a second, and kills it" do
          expect(calls).to eq [["TERM", sign * 42], [:sleep, 1], ["KILL", sign * 42]]
        end

        it "resets the journal" do
          expect(File.exist?(filename)).to be false
        end

        it "logs both signals" do
          expect(log).to eq cleanup_log([42], [:info, "Termed old #{label} 42"], [:info, "Killed old #{label} 42"])
        end
      end

      context "with ids that survive TERM, and some that exit during the wait" do
        before do
          write_journal(filename, [42, 43, 44])
          alive = {42 => true, 43 => true, 44 => false}
          allow(Bluepill::System).to receive(:pid_alive?) { |id| alive[sign * id] }
          allow(described_class).to(receive(:sleep)) do |seconds|
            calls << [:sleep, seconds]
            alive[43] = false
          end
          missing("KILL", 42)
          described_class.kill_all(journal_kind, "app")
        end

        it "only kills the ids still alive after the wait" do
          terms = [["TERM", sign * 42], ["TERM", sign * 43], ["TERM", sign * 44]]
          expect(calls).to eq [*terms, [:sleep, 1], ["KILL", sign * 42]]
        end

        it "resets the journal" do
          expect(File.exist?(filename)).to be false
        end

        it "logs one that exited before KILL reached it" do
          expect(log).to include([:debug, "Unable to kill missing #{label} 42"])
        end
      end
    end
  end

  {"pgid" => described_class::PGID, "pid" => described_class::PID}.each do |kind, journal_kind|
    describe ".append of a #{kind}" do
      let(:filename) { journal_kind.filename(dir, "app") }

      before do
        allow(described_class).to receive(:acquire_atomic_fs_lock).and_call_original
        allow(File).to receive(:open).and_call_original
      end

      # The log of an append, which reads the journal under its lock
      define_method(:append_log) do |*lines|
        [
          [:debug, "Acquired lock #{filename}.lock"],
          [:debug, "#{kind} journal file: #{filename}"],
          *lines,
          [:debug, "Cleared lock #{filename}.lock"]
        ]
      end

      context "when a new #{kind} is appended" do
        before do
          described_class.append(journal_kind, "app", 42)
        end

        it "journals it" do
          expect(File.read(filename)).to eq "42\n"
        end

        it "keeps the journal private" do
          expect(modes(filename)).to eq [0o600]
        end

        it "logs it, under the journal lock" do
          expect(log).to eq append_log(
            [:debug, "Saving #{kind} 42 to process journal app"],
            [:info, "Saved #{kind} 42 to journal app"],
            [:debug, "Journal now = 42\n"]
          )
        end
      end

      context "when the #{kind} is appended again" do
        before do
          described_class.append(journal_kind, "app", 42)
          log.clear
          described_class.append(journal_kind, "app", 42)
        end

        it "journals it once" do
          expect(File.read(filename)).to eq "42\n"
        end

        it "opens the journal to append to it once" do
          expect(File).to have_received(:open).with(filename, "a+", 0o600).once
        end

        it "takes the journal lock each time" do
          expect(described_class).to have_received(:acquire_atomic_fs_lock).with(filename).twice
        end

        it "logs that it skipped the duplicate, under the journal lock" do
          expect(log).to eq append_log(
            [:debug, "#{kind} journal = 42"],
            [:debug, "Skipping duplicate #{kind} 42 already in journal app"]
          )
        end
      end

      it "yields a valid #{kind} before it journals it" do
        journaled = nil
        described_class.append(journal_kind, "app", 42) { |id| journaled = [id, File.exist?(filename)] }
        expect(journaled).to eq [42, false]
      end

      it "journals when the #{kind}'s process started" do
        allow(Bluepill::System).to receive(:started_at).with(42).and_return(1000)
        described_class.append(journal_kind, "app", 42)
        expect(File.read(filename)).to eq "42 1000\n"
      end

      [nil, 0, 1, "42"].each do |id|
        context "with the invalid #{kind} #{id.inspect}" do
          before do
            described_class.append(journal_kind, "app", id)
          end

          it "skips it" do
            expect(File.exist?(filename)).to be false
          end

          it "yields nothing" do
            expect { |block| described_class.append(journal_kind, "app", id, &block) }.not_to yield_control
          end

          it "logs that it skipped it" do
            expect(log).to eq [[:debug, "Skipping invalid #{kind} #{id} (class #{id.class})"]]
          end
        end
      end
    end
  end

  describe ".journal_entries" do
    it "reads each id, with when its process started if the line says" do
      filename = File.join(dir, "journal")
      File.write(filename, "42 1000\n43\n\n")
      expect(described_class.journal_entries(filename)).to eq [[42, 1000], [43, nil], [0, nil]]
    end

    it "reads a garbled start time as 0, which no running process started at" do
      filename = File.join(dir, "journal")
      File.write(filename, "42 junk\n")
      expect(described_class.journal_entries(filename)).to eq [[42, 0]]
    end
  end

  describe ".journal_line" do
    it "has the id and when its process started" do
      allow(Bluepill::System).to receive(:started_at).with(42).and_return(1000)
      expect(described_class.journal_line(42)).to eq "42 1000"
    end

    it "has only the id when ps can't tell when it started" do
      expect(described_class.journal_line(42)).to eq "42"
    end
  end

  describe ".journaled_ids" do
    let(:filename) { File.join(dir, "journal") }
    let(:boot) { 10_000 }

    before do
      File.write(filename, "42 20000\n43\n")
      File.utime(boot + 5, boot + 5, filename)
      allow(Bluepill::System).to receive(:boot_time).and_return(boot)
    end

    def journaled(started)
      allow(Bluepill::System).to receive(:started_at).with(42).and_return(started)
      described_class.journaled_ids(filename, [42], described_class::PID)
    end

    # The journaled ids of 43, which has no start time in the journal
    def journaled_without_start_time
      allow(Bluepill::System).to receive(:started_at).with(43).and_return(30_000)
      described_class.journaled_ids(filename, [43], described_class::PID)
    end

    it "keeps a running process that started when the journal says" do
      expect([20_000, 20_002, 19_998].collect { |started| journaled(started) }).to eq [[42], [42], [42]]
    end

    it "doesn't log the ones it keeps" do
      [20_000, 20_002, 19_998].each { |started| journaled(started) }
      expect(log).to eq []
    end

    it "skips a running process that started at another time" do
      expect([20_003, 19_997].collect { |started| journaled(started) }).to eq [[], []]
    end

    it "logs the ones it skips" do
      [20_003, 19_997].each { |started| journaled(started) }
      expect(log).to eq [[:info, "Skipping old process 42, which isn't the one bluepill started"]] * 2
    end

    it "keeps an exited one that was journaled since the machine booted" do
      File.write(filename, "42 #{boot - 2}\n")
      expect(journaled(nil)).to eq [42]
    end

    it "skips an exited one that was journaled before the machine booted" do
      File.write(filename, "42 #{boot - 3}\n")
      expect(journaled(nil)).to eq []
    end

    it "keeps one without a start time if the journal was written since the machine booted" do
      expect(journaled_without_start_time).to eq [43]
    end

    it "keeps one without a start time if the journal was written up to 2 seconds before the machine booted" do
      File.utime(boot - 2, boot - 2, filename)
      expect(journaled_without_start_time).to eq [43]
    end

    it "skips one without a start time if the journal was written before the machine booted" do
      File.utime(boot - 3, boot - 3, filename)
      expect(described_class.journaled_ids(filename, [43], described_class::PID)).to eq []
    end

    it "only keeps a running process that started when the journal says if ps can't tell when the machine booted" do
      allow(Bluepill::System).to receive(:boot_time).and_return(nil)
      kept = [journaled(20_000), journaled(nil), described_class.journaled_ids(filename, [43], described_class::PID)]
      expect(kept).to eq [[42], [], []]
    end

    it "keeps nothing if the journal was cleared since its ids were read" do
      File.delete(filename)
      expect(described_class.journaled_ids(filename, [42], described_class::PID)).to eq []
    end
  end

  describe "Journal#append" do
    let(:filename) { described_class::PID.filename(dir, "app") }
    let(:journal) { described_class.for("app") }

    # Return what the pid and pgid journals say, or false for one that isn't there
    def journals
      pgid_filename = described_class::PGID.filename(dir, "app")
      {pid: File.read(filename), pgid: File.exist?(pgid_filename) && File.read(pgid_filename)}
    end

    it "journals when the process and its group leader started" do
      allow(::Process).to receive(:getpgid).with(42).and_return(40)
      allow(Bluepill::System).to receive(:started_at).with(42).and_return(1000)
      allow(Bluepill::System).to receive(:started_at).with(40).and_return(900)
      journal.append(42)
      expect(journals).to eq(pid: "42 1000\n", pgid: "40 900\n")
    end

    context "when appended twice" do
      before do
        allow(::Process).to receive(:getpgid).with(42).and_return(40)
        2.times { journal.append(42) }
      end

      it "journals the pid and its process group once" do
        expect(journals).to eq(pid: "42\n", pgid: "40\n")
      end

      it "looks up the process group each time" do
        expect(::Process).to have_received(:getpgid).twice
      end
    end

    context "with an invalid pid" do
      before do
        allow(::Process).to receive(:getpgid)
        journal.append(1)
      end

      it "journals nothing" do
        expect([filename, described_class::PGID.filename(dir, "app")].select { |path| File.exist?(path) }).to be_empty
      end

      it "doesn't look up its process group" do
        expect(::Process).not_to have_received(:getpgid)
      end
    end

    context "when the process is gone before its group is looked up" do
      before do
        allow(::Process).to receive(:getpgid).with(42).and_raise(Errno::ESRCH)
        journal.append(42)
      end

      it "journals only the pid" do
        expect(journals).to eq(pid: "42\n", pgid: false)
      end

      it "looks up the process group once" do
        expect(::Process).to have_received(:getpgid).once
      end
    end
  end
end
