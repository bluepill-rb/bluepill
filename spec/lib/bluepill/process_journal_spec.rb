require 'tmpdir'

describe Bluepill::ProcessJournal do
  let(:log) { [] }
  let(:logger) do
    instance_double(Bluepill::Logger).tap do |logger|
      allow(logger).to(receive(:debug)) { |message| log << [:debug, message] }
      allow(logger).to(receive(:info)) { |message| log << [:info, message] }
    end
  end
  let(:journal) { described_class }
  # The journal directory before 0.2, and the app's journal directory in it
  let(:legacy_dir) { Dir.mktmpdir }
  let(:dir) { File.join(legacy_dir, 'app').tap { |app_dir| Dir.mkdir(app_dir) } }

  around do |example|
    old_logger = journal.instance_variable_get(:@logger)
    old_base_dir = journal.instance_variable_get(:@journal_base_dir)
    old_legacy_dir = journal.instance_variable_get(:@legacy_journal_dir)
    begin
      example.run
    ensure
      journal.instance_variable_set(:@logger, old_logger)
      journal.instance_variable_set(:@journal_base_dir, old_base_dir)
      journal.instance_variable_set(:@legacy_journal_dir, old_legacy_dir)
    end
  end

  before do
    journal.instance_variable_set(:@logger, logger)
    journal.instance_variable_set(:@journal_base_dir, dir)
    journal.instance_variable_set(:@legacy_journal_dir, legacy_dir)
    allow(journal).to receive(:sleep)
    allow(::Process).to receive(:kill)
    # Ids without a start time, journaled since the machine booted
    allow(Bluepill::System).to receive_messages(pid_alive?: false, started_at: nil, boot_time: 0)
  end

  after do
    FileUtils.remove_entry(legacy_dir)
  end

  def write_journal(filename, ids)
    File.open(filename, 'w') { |f| ids.each { |id| f.puts(id) } }
  end

  def lock_log(filename)
    [[:debug, "Acquired lock #{filename}.lock"], [:debug, "Cleared lock #{filename}.lock"]]
  end

  describe '.logger=' do
    it 'only sets the logger once' do
      journal.instance_variable_set(:@logger, nil)
      journal.logger = logger
      journal.logger = instance_double(Bluepill::Logger)
      expect(journal.logger).to eq logger
    end
  end

  describe '.setup' do
    before do
      journal.instance_variable_set(:@journal_base_dir, nil)
      journal.instance_variable_set(:@legacy_journal_dir, nil)
    end

    it "creates the app's journal directory once" do
      journal.setup(dir, :web)
      legacy = File.join(dir, 'journals')
      expected = File.join(legacy, 'web')
      expect(journal.journal_base_dir).to eq expected
      expect(journal.legacy_journal_dir).to eq legacy
      [legacy, expected].each do |dir|
        expect(File.directory?(dir)).to be true
        expect(File.stat(dir).mode & 0o777).to eq 0o777
      end

      journal.setup(File.join(dir, 'other'), :api)
      expect(journal.journal_base_dir).to eq expected
      expect(journal.legacy_journal_dir).to eq legacy
      expect(File.exist?(File.join(dir, 'other'))).to be false
      expect(File.exist?(File.join(legacy, 'api'))).to be false
    end

    it 'only makes the journal directories writable if they exist' do
      legacy = File.join(dir, 'journals')
      Dir.mkdir(legacy, 0o700)
      Dir.mkdir(File.join(legacy, 'web'), 0o700)
      journal.setup(dir, 'web')
      expect(File.stat(legacy).mode & 0o777).to eq 0o777
      expect(File.stat(File.join(legacy, 'web')).mode & 0o777).to eq 0o777
    end
  end

  describe '.journal_dirs' do
    it "lists the app's journal directory, then the one before 0.2" do
      expect(journal.journal_dirs).to eq [dir, legacy_dir]
    end
  end

  [:skip_pid?, :skip_pgid?].each do |method|
    describe ".#{method}" do
      it 'skips non-integers and ids <= 1' do
        expect(journal.send(method, nil)).to be true
        expect(journal.send(method, '5')).to be true
        expect(journal.send(method, -5)).to be true
        expect(journal.send(method, 0)).to be true
        expect(journal.send(method, 1)).to be true
        expect(journal.send(method, 2)).to be false
      end

      # On Ruby before 2.4 ids are Fixnums or Bignums, subclasses of Integer
      it 'accepts instances of Integer subclasses' do
        id = instance_double(Integer)
        allow(id).to receive(:is_a?).with(Integer).and_return(true)
        allow(id).to receive(:<=).with(1).and_return(false)
        expect(journal.send(method, id)).to be false
      end
    end
  end

  describe '.acquire_atomic_fs_lock' do
    let(:name) { File.join(dir, 'journal') }

    it 'holds a private lock directory while yielding and removes it afterwards' do
      held = nil
      mode = nil
      old_umask = File.umask(0o022)
      begin
        result = journal.acquire_atomic_fs_lock(name) do
          held = File.directory?("#{name}.lock")
          mode = File.stat("#{name}.lock").mode & 0o777
          :result
        end
        expect(result).to eq :result
      ensure
        File.umask(old_umask)
      end
      expect(held).to be true
      expect(mode).to eq 0o700
      expect(File.exist?("#{name}.lock")).to be false
      expect(log).to eq lock_log(name)
    end

    it 'waits until the lock is released' do
      Dir.mkdir("#{name}.lock")
      yielded = false
      allow(journal).to(receive(:sleep) { Dir.rmdir("#{name}.lock") })
      journal.acquire_atomic_fs_lock(name) { yielded = true }
      expect(journal).to have_received(:sleep).with(1).once
      expect(yielded).to be true
      expect(File.exist?("#{name}.lock")).to be false
      expect(File.exist?("#{name}.lock.lock")).to be false
      expect(log).to eq [[:debug, "Waiting for lock #{name}.lock"]] + lock_log(name)
    end

    it 'gives up after 10 attempts without removing the other lock' do
      Dir.mkdir("#{name}.lock")
      expect do
        journal.acquire_atomic_fs_lock(name) { raise 'should not yield' }
      end.to raise_error("Timeout waiting for lock #{name}.lock")
      expect(journal).to have_received(:sleep).with(1).exactly(9).times
      expect(File.directory?("#{name}.lock")).to be true
      expect(log).to eq ([[:debug, "Waiting for lock #{name}.lock"]] * 9) +
        [[:info, "Timeout waiting for lock #{name}.lock"]]
    end

    it 'removes the lock when the block raises' do
      expect do
        journal.acquire_atomic_fs_lock(name) { raise Errno::EEXIST }
      end.to raise_error(Errno::EEXIST)
      expect(File.exist?("#{name}.lock")).to be false
      expect(log).to eq lock_log(name)
    end
  end

  describe '.clear_atomic_fs_lock' do
    it 'does nothing when the lock does not exist' do
      allow(Dir).to receive(:rmdir).and_call_original
      journal.clear_atomic_fs_lock(File.join(dir, 'missing.lock'))
      expect(Dir).not_to have_received(:rmdir)
      expect(log).to eq []
    end

    it 'removes the lock directory' do
      lock = File.join(dir, 'journal.lock')
      Dir.mkdir(lock)
      journal.clear_atomic_fs_lock(lock)
      expect(File.exist?(lock)).to be false
      expect(log).to eq [[:debug, "Cleared lock #{lock}"]]
    end
  end

  describe '.clear_all_atomic_fs_locks' do
    it "removes the app's lock directories, and nothing else" do
      lock = File.join(dir, '.bluepill_pids_journal.web.lock')
      file = File.join(dir, '.b.lock')
      other_app = File.join(legacy_dir, 'other')
      other_lock = File.join(other_app, '.bluepill_pids_journal.web.lock')
      legacy_lock = File.join(legacy_dir, '.bluepill_pids_journal.web.lock')
      [lock, other_app, other_lock, legacy_lock].each { |dir| Dir.mkdir(dir) }
      File.write(file, '')
      Dir.chdir(legacy_dir) { journal.clear_all_atomic_fs_locks }
      expect(File.exist?(lock)).to be false
      expect(File.exist?(file)).to be true
      expect(File.directory?(other_lock)).to be true
      expect(File.directory?(legacy_lock)).to be true
      expect(log).to eq [[:debug, "Cleared lock #{lock}"]]
    end
  end

  describe '.pid_journal_filename' do
    it 'is in the journal directory' do
      expect(journal.pid_journal_filename('app')).to eq File.join(dir, '.bluepill_pids_journal.app')
    end

    it 'is in another journal directory when given one' do
      expect(journal.pid_journal_filename('app', '/old')).to eq '/old/.bluepill_pids_journal.app'
    end
  end

  describe '.pgid_journal_filename' do
    it 'is in the journal directory' do
      expect(journal.pgid_journal_filename('app')).to eq File.join(dir, '.bluepill_pgids_journal.app')
    end

    it 'is in another journal directory when given one' do
      expect(journal.pgid_journal_filename('app', '/old')).to eq '/old/.bluepill_pgids_journal.app'
    end
  end

  {pid_journal: 'pid', pgid_journal: 'pgid'}.each do |method, kind|
    describe ".#{method}" do
      it 'reads valid ids' do
        filename = File.join(dir, 'j')
        write_journal(filename, [0, 1, 42, 43])
        expect(journal.send(method, filename)).to eq [42, 43]
        expect(log).to eq [
          [:debug, "#{kind} journal file: #{filename}"],
          [:debug, "#{kind} journal = 42 43"],
        ]
      end

      it 'is empty without a journal' do
        filename = File.join(dir, 'missing')
        expect(journal.send(method, filename)).to eq []
        expect(log).to eq [[:debug, "#{kind} journal file: #{filename}"]]
      end
    end
  end

  describe '.kill_all_from_journal' do
    it 'kills pids and pgids' do
      allow(journal).to receive(:kill_all_pids_from_journal)
      allow(journal).to receive(:kill_all_pgids_from_journal)
      journal.kill_all_from_journal('app')
      expect(journal).to have_received(:kill_all_pids_from_journal).with('app').once
      expect(journal).to have_received(:kill_all_pgids_from_journal).with('app').once
    end
  end

  {
    kill_all_pids_from_journal: [:pid_journal_filename, 1, 'process', 'pid'],
    kill_all_pgids_from_journal: [:pgid_journal_filename, -1, 'process group', 'pgid'],
  }.each do |method, (filename_method, sign, label, kind)|
    describe ".#{method}" do
      let(:filename) { journal.send(filename_method, 'app') }
      let(:legacy_filename) { journal.send(filename_method, 'app', legacy_dir) }

      define_method(:journal_log) do |ids|
        [[:debug, "#{kind} journal file: #{filename}"], [:debug, "#{kind} journal = #{ids.join(' ')}"]]
      end

      # Reading the journal that bluepill 0.1 and earlier shared, after the app's
      define_method(:no_legacy_journal_log) do
        [[:debug, "#{kind} journal file: #{legacy_filename}"], [:debug, 'No previous process journal - Skipping cleanup']]
      end

      it 'skips cleanup without a journal' do
        allow(Bluepill::System).to receive(:delete_if_exists)
        journal.send(method, 'app')
        expect(::Process).not_to have_received(:kill)
        expect(Bluepill::System).not_to have_received(:delete_if_exists)
        expect(log).to eq [
          [:debug, "#{kind} journal file: #{filename}"],
          [:debug, 'No previous process journal - Skipping cleanup'],
        ] + no_legacy_journal_log
      end

      it 'also kills what the journal from before 0.2 lists, and resets it' do
        write_journal(filename, [42])
        write_journal(legacy_filename, [43])
        journal.send(method, 'app')
        expect(::Process).to have_received(:kill).with('TERM', sign * 42).once.ordered
        expect(::Process).to have_received(:kill).with('TERM', sign * 43).once.ordered
        expect(File.exist?(filename)).to be false
        expect(File.exist?(legacy_filename)).to be false
        expect(File.exist?("#{legacy_filename}.lock")).to be false
        expect(log).to include([:info, "Termed old #{label} 43"])
      end

      it 'leaves alone an id that now belongs to another process, and resets the journal' do
        File.write(filename, "42 20000\n")
        allow(Bluepill::System).to receive(:started_at).with(42).and_return(50_000)
        journal.send(method, 'app')
        expect(::Process).not_to have_received(:kill)
        expect(File.exist?(filename)).to be false
        expect(log).to include([:info, "Skipping old #{label} 42, which isn't the one bluepill started"])
      end

      it "doesn't touch another app's journal" do
        other = journal.send(filename_method, 'app', File.join(legacy_dir, 'other'))
        Dir.mkdir(File.dirname(other))
        write_journal(other, [44])
        journal.send(method, 'app')
        expect(::Process).not_to have_received(:kill)
        expect(File.read(other)).to eq "44\n"
      end

      it 'terms the journaled ids and resets the journal' do
        write_journal(filename, [42, 43])
        allow(::Process).to receive(:kill).with('TERM', sign * 43).and_raise(Errno::ESRCH)
        journal.send(method, 'app')
        expect(::Process).to have_received(:kill).with('TERM', sign * 42).once
        expect(journal).not_to have_received(:sleep)
        expect(File.exist?(filename)).to be false
        expect(File.exist?("#{filename}.lock")).to be false
        expect(log).to eq journal_log([42, 43]) + [
          [:debug, "Acquired lock #{filename}.lock"],
          [:info, "Termed old #{label} 42"],
          [:debug, "Unable to term missing #{label} 43"],
          [:debug, 'Journal cleanup completed'],
          [:debug, "Cleared lock #{filename}.lock"],
        ] + no_legacy_journal_log
      end

      it 'kills a single id that survives TERM' do
        write_journal(filename, [42])
        allow(Bluepill::System).to receive(:pid_alive?).with(sign * 42).and_return(true)
        journal.send(method, 'app')
        expect(::Process).to have_received(:kill).with('TERM', sign * 42).once
        expect(journal).to have_received(:sleep).with(1).once
        expect(::Process).to have_received(:kill).with('KILL', sign * 42).once
        expect(File.exist?(filename)).to be false
        expect(log).to eq journal_log([42]) + [
          [:debug, "Acquired lock #{filename}.lock"],
          [:info, "Termed old #{label} 42"],
          [:info, "Killed old #{label} 42"],
          [:debug, 'Journal cleanup completed'],
          [:debug, "Cleared lock #{filename}.lock"],
        ] + no_legacy_journal_log
      end

      it 'only kills ids still alive after the wait' do
        write_journal(filename, [42, 43, 44])
        alive = {42 => true, 43 => true, 44 => false}
        allow(Bluepill::System).to receive(:pid_alive?) { |id| alive[sign * id] }
        allow(journal).to(receive(:sleep) { alive[43] = false })
        allow(::Process).to receive(:kill).with('KILL', sign * 42).and_raise(Errno::ESRCH)
        journal.send(method, 'app')
        expect(journal).to have_received(:sleep).with(1).once
        expect(::Process).not_to have_received(:kill).with('KILL', sign * 43)
        expect(::Process).not_to have_received(:kill).with('KILL', sign * 44)
        expect(File.exist?(filename)).to be false
        expect(log).to include([:debug, "Unable to kill missing #{label} 42"])
      end
    end
  end

  {append_pgid_to_journal: 'pgid', append_pid_to_journal: 'pid'}.each do |method, kind|
    describe ".#{method}" do
      let(:filename) { journal.send("#{kind}_journal_filename", 'app') }

      before do
        allow(::Process).to receive(:getpgid).with(42).and_raise(Errno::ESRCH)
      end

      it "appends new #{kind}s once, under the journal lock" do
        allow(journal).to receive(:acquire_atomic_fs_lock).and_call_original
        allow(File).to receive(:open).and_call_original
        journal.send(method, 'app', 42)
        expect(log).to eq [
          [:debug, "Acquired lock #{filename}.lock"],
          [:debug, "#{kind} journal file: #{filename}"],
          [:debug, "Saving #{kind} 42 to process journal app"],
          [:info, "Saved #{kind} 42 to journal app"],
          [:debug, "Journal now = 42\n"],
          [:debug, "Cleared lock #{filename}.lock"],
        ]
        log.clear
        journal.send(method, 'app', 42)
        expect(log).to eq [
          [:debug, "Acquired lock #{filename}.lock"],
          [:debug, "#{kind} journal file: #{filename}"],
          [:debug, "#{kind} journal = 42"],
          [:debug, "Skipping duplicate #{kind} 42 already in journal app"],
          [:debug, "Cleared lock #{filename}.lock"],
        ]
        expect(File.read(filename)).to eq "42\n"
        expect(File.stat(filename).mode & 0o777).to eq 0o600
        expect(journal).to have_received(:acquire_atomic_fs_lock).with(filename).twice
        expect(File).to have_received(:open).with(filename, 'a+', 0o600).once
      end

      it "journals when the #{kind}'s process started" do
        allow(Bluepill::System).to receive(:started_at).with(42).and_return(1000)
        journal.send(method, 'app', 42)
        expect(File.read(filename)).to eq "42 1000\n"
      end

      [nil, 0, 1, '42'].each do |id|
        it "skips the invalid #{kind} #{id.inspect}" do
          allow(::Process).to receive(:getpgid)
          journal.send(method, 'app', id)
          expect(::Process).not_to have_received(:getpgid)
          expect(File.exist?(filename)).to be false
          expect(log).to eq [[:debug, "Skipping invalid #{kind} #{id} (class #{id.class})"]]
        end
      end
    end
  end

  describe '.journal_entries' do
    it 'reads each id, with when its process started if the line says' do
      filename = File.join(dir, 'journal')
      File.write(filename, "42 1000\n43\n\n")
      expect(journal.journal_entries(filename)).to eq [[42, 1000], [43, nil], [0, nil]]
    end

    it 'reads a garbled start time as 0, which no running process started at' do
      filename = File.join(dir, 'journal')
      File.write(filename, "42 junk\n")
      expect(journal.journal_entries(filename)).to eq [[42, 0]]
    end
  end

  describe '.journal_line' do
    it 'has the id and when its process started' do
      allow(Bluepill::System).to receive(:started_at).with(42).and_return(1000)
      expect(journal.journal_line(42)).to eq '42 1000'
    end

    it "has only the id when ps can't tell when it started" do
      expect(journal.journal_line(42)).to eq '42'
    end
  end

  describe '.journaled_ids' do
    let(:filename) { File.join(dir, 'journal') }
    let(:boot) { 10_000 }

    before do
      File.write(filename, "42 20000\n43\n")
      File.utime(boot + 5, boot + 5, filename)
      allow(Bluepill::System).to receive(:boot_time).and_return(boot)
    end

    def journaled(started)
      allow(Bluepill::System).to receive(:started_at).with(42).and_return(started)
      journal.journaled_ids(filename, [42], 'process')
    end

    it 'keeps a running process that started when the journal says' do
      expect(journaled(20_000)).to eq [42]
      expect(journaled(20_002)).to eq [42]
      expect(journaled(19_998)).to eq [42]
      expect(log).to eq []
    end

    it 'skips a running process that started at another time' do
      expect(journaled(20_003)).to eq []
      expect(journaled(19_997)).to eq []
      expect(log).to eq [[:info, "Skipping old process 42, which isn't the one bluepill started"]] * 2
    end

    it 'keeps an exited one that was journaled since the machine booted' do
      File.write(filename, "42 #{boot - 2}\n")
      expect(journaled(nil)).to eq [42]
    end

    it 'skips an exited one that was journaled before the machine booted' do
      File.write(filename, "42 #{boot - 3}\n")
      expect(journaled(nil)).to eq []
    end

    it 'keeps one without a start time if the journal was written since the machine booted' do
      allow(Bluepill::System).to receive(:started_at).with(43).and_return(30_000)
      expect(journal.journaled_ids(filename, [43], 'process')).to eq [43]
      File.utime(boot - 2, boot - 2, filename)
      expect(journal.journaled_ids(filename, [43], 'process')).to eq [43]
    end

    it 'skips one without a start time if the journal was written before the machine booted' do
      File.utime(boot - 3, boot - 3, filename)
      expect(journal.journaled_ids(filename, [43], 'process')).to eq []
    end

    it "only keeps a running process that started when the journal says if ps can't tell when the machine booted" do
      allow(Bluepill::System).to receive(:boot_time).and_return(nil)
      expect(journaled(20_000)).to eq [42]
      expect(journaled(nil)).to eq []
      expect(journal.journaled_ids(filename, [43], 'process')).to eq []
    end

    it 'keeps nothing if the journal was cleared since its ids were read' do
      File.delete(filename)
      expect(journal.journaled_ids(filename, [42], 'process')).to eq []
    end
  end

  describe '.append_pid_to_journal' do
    let(:filename) { journal.pid_journal_filename('app') }

    it 'journals when the process and its group leader started' do
      allow(::Process).to receive(:getpgid).with(42).and_return(40)
      allow(Bluepill::System).to receive(:started_at).with(42).and_return(1000)
      allow(Bluepill::System).to receive(:started_at).with(40).and_return(900)
      journal.append_pid_to_journal('app', 42)
      expect(File.read(filename)).to eq "42 1000\n"
      expect(File.read(journal.pgid_journal_filename('app'))).to eq "40 900\n"
    end

    it 'journals the pid and its process group' do
      allow(::Process).to receive(:getpgid).with(42).and_return(40)
      journal.append_pid_to_journal('app', 42)
      journal.append_pid_to_journal('app', 42)
      expect(::Process).to have_received(:getpgid).twice
      expect(File.read(filename)).to eq "42\n"
      expect(File.read(journal.pgid_journal_filename('app'))).to eq "40\n"
    end

    it 'ignores missing processes when looking up the process group' do
      allow(::Process).to receive(:getpgid).with(42).and_raise(Errno::ESRCH)
      journal.append_pid_to_journal('app', 42)
      expect(::Process).to have_received(:getpgid).once
      expect(File.read(filename)).to eq "42\n"
      expect(File.exist?(journal.pgid_journal_filename('app'))).to be false
    end
  end
end
