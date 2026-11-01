require 'tmpdir'

describe Bluepill::ProcessJournal do
  let(:logger) { instance_double(Bluepill::Logger).as_null_object }
  let(:journal) { described_class }

  around do |example|
    old_logger = journal.instance_variable_get(:@logger)
    old_base_dir = journal.instance_variable_get(:@journal_base_dir)
    Dir.mktmpdir do |dir|
      @dir = dir
      begin
        example.run
      ensure
        journal.instance_variable_set(:@logger, old_logger)
        journal.instance_variable_set(:@journal_base_dir, old_base_dir)
      end
    end
  end

  before do
    journal.instance_variable_set(:@logger, logger)
    journal.instance_variable_set(:@journal_base_dir, @dir)
    allow(journal).to receive(:sleep)
    allow(::Process).to receive(:kill)
    allow(Bluepill::System).to receive(:pid_alive?).and_return(false)
  end

  def write_journal(filename, ids)
    File.open(filename, 'w') { |f| ids.each { |id| f.puts(id) } }
  end

  describe '.logger=' do
    it 'only sets the logger once' do
      journal.instance_variable_set(:@logger, nil)
      journal.logger = logger
      journal.logger = double('other logger')
      expect(journal.logger).to eq logger
    end
  end

  describe '.base_dir=' do
    it 'creates the journal directory once' do
      journal.instance_variable_set(:@journal_base_dir, nil)
      journal.base_dir = @dir
      expected = File.join(@dir, 'journals')
      expect(journal.journal_base_dir).to eq expected
      expect(File.directory?(expected)).to be true
      expect(File.stat(expected).mode & 0777).to eq 0777

      journal.base_dir = File.join(@dir, 'other')
      expect(journal.journal_base_dir).to eq expected
      expect(File.exist?(File.join(@dir, 'other'))).to be false
    end
  end

  describe '.skip_pid? and .skip_pgid?' do
    [:skip_pid?, :skip_pgid?].each do |method|
      it "#{method} skips non-integers and pids <= 1" do
        expect(journal.send(method, nil)).to be true
        expect(journal.send(method, '5')).to be true
        expect(journal.send(method, 1)).to be true
        expect(journal.send(method, 2)).to be false
      end
    end
  end

  describe '.acquire_atomic_fs_lock' do
    let(:name) { File.join(@dir, 'journal') }

    it 'holds a lock directory while yielding and removes it afterwards' do
      held = nil
      journal.acquire_atomic_fs_lock(name) { held = File.directory?("#{name}.lock") }
      expect(held).to be true
      expect(File.exist?("#{name}.lock")).to be false
    end

    it 'waits until the lock is released' do
      Dir.mkdir("#{name}.lock")
      yielded = false
      expect(journal).to receive(:sleep).with(1).once { Dir.rmdir("#{name}.lock") }
      expect(logger).to receive(:debug).with("Waiting for lock #{name}.lock")
      journal.acquire_atomic_fs_lock(name) { yielded = true }
      expect(yielded).to be true
      expect(File.exist?("#{name}.lock")).to be false
      expect(File.exist?("#{name}.lock.lock")).to be false
    end

    it 'gives up after 10 attempts without removing the other lock' do
      Dir.mkdir("#{name}.lock")
      expect(journal).to receive(:sleep).with(1).exactly(9).times
      expect(logger).to receive(:info).with("Timeout waiting for lock #{name}.lock")
      expect do
        journal.acquire_atomic_fs_lock(name) { raise 'should not yield' }
      end.to raise_error("Timeout waiting for lock #{name}.lock")
      expect(File.directory?("#{name}.lock")).to be true
    end

    it 'removes the lock when the block raises' do
      expect do
        journal.acquire_atomic_fs_lock(name) { raise Errno::EEXIST }
      end.to raise_error(Errno::EEXIST)
      expect(File.exist?("#{name}.lock")).to be false
    end
  end

  describe '.clear_atomic_fs_lock' do
    it 'does nothing when the lock does not exist' do
      expect(Dir).not_to receive(:rmdir)
      journal.clear_atomic_fs_lock(File.join(@dir, 'missing.lock'))
    end
  end

  describe '.clear_all_atomic_fs_locks' do
    it 'deletes lock directories' do
      dir_lock = File.join(@dir, '.a.lock')
      file_lock = File.join(@dir, '.b.lock')
      Dir.mkdir(dir_lock)
      File.open(file_lock, 'w') {}
      allow(Dir).to receive(:[]).with('.*.lock').and_return([dir_lock, file_lock])
      expect(Bluepill::System).to receive(:delete_if_exists).with(dir_lock)
      expect(Bluepill::System).not_to receive(:delete_if_exists).with(file_lock)
      journal.clear_all_atomic_fs_locks
    end
  end

  describe '.pid_journal and .pgid_journal' do
    [:pid_journal, :pgid_journal].each do |method|
      it "#{method} reads valid ids" do
        filename = File.join(@dir, 'j')
        write_journal(filename, [0, 1, 42, 43])
        expect(journal.send(method, filename)).to eq [42, 43]
      end

      it "#{method} is empty without a journal" do
        expect(journal.send(method, File.join(@dir, 'missing'))).to eq []
      end
    end
  end

  describe '.kill_all_from_all_journals' do
    it 'kills every journal found, ignoring locks' do
      allow(Dir).to receive(:[]).with('.bluepill_pids_journal.*').
        and_return(['.bluepill_pids_journal.foo', '.bluepill_pids_journal.foo.lock'])
      expect(journal).to receive(:kill_all_from_journal).once.with('foo')
      journal.kill_all_from_all_journals
    end
  end

  describe '.kill_all_from_journal' do
    it 'kills pids and pgids' do
      expect(journal).to receive(:kill_all_pids_from_journal).with('app')
      expect(journal).to receive(:kill_all_pgids_from_journal).with('app')
      journal.kill_all_from_journal('app')
    end
  end

  {
    kill_all_pids_from_journal: [:pid_journal_filename, 1, 'process'],
    kill_all_pgids_from_journal: [:pgid_journal_filename, -1, 'process group'],
  }.each do |method, (filename_method, sign, label)|
    describe ".#{method}" do
      let(:filename) { journal.send(filename_method, 'app') }

      it 'skips cleanup without a journal' do
        expect(::Process).not_to receive(:kill)
        expect(logger).to receive(:debug).with('No previous process journal - Skipping cleanup')
        journal.send(method, 'app')
      end

      it 'terms the journaled ids and resets the journal' do
        write_journal(filename, [42, 43])
        expect(::Process).to receive(:kill).with('TERM', sign * 42)
        expect(::Process).to receive(:kill).with('TERM', sign * 43).and_raise(Errno::ESRCH)
        expect(logger).to receive(:info).with("Termed old #{label} 42")
        expect(logger).to receive(:debug).with("Unable to term missing #{label} 43")
        expect(journal).not_to receive(:sleep)
        journal.send(method, 'app')
        expect(File.exist?(filename)).to be false
        expect(File.exist?("#{filename}.lock")).to be false
      end

      it 'kills the journaled ids when more than one survives' do
        write_journal(filename, [42, 43])
        allow(Bluepill::System).to receive(:pid_alive?).and_return(true)
        expect(journal).to receive(:sleep).with(1)
        expect(::Process).to receive(:kill).with('KILL', sign * 42)
        expect(::Process).to receive(:kill).with('KILL', sign * 43).and_raise(Errno::ESRCH)
        expect(logger).to receive(:info).with("Killed old #{label} 42")
        expect(logger).to receive(:debug).with("Unable to kill missing #{label} 43")
        journal.send(method, 'app')
        expect(File.exist?(filename)).to be false
      end
    end
  end

  describe '.append_pgid_to_journal' do
    let(:filename) { journal.pgid_journal_filename('app') }

    it 'skips invalid pgids' do
      expect(logger).to receive(:debug).with(/\ASkipping invalid pgid 1 \(class /)
      journal.append_pgid_to_journal('app', 1)
      expect(File.exist?(filename)).to be false
    end

    it 'appends new pgids once' do
      journal.append_pgid_to_journal('app', 42)
      expect(logger).to receive(:debug).with('Skipping duplicate pgid 42 already in journal app')
      journal.append_pgid_to_journal('app', 42)
      journal.append_pgid_to_journal('app', 43)
      expect(File.read(filename)).to eq "42\n43\n"
      expect(File.stat(filename).mode & 0777).to eq 0600
    end
  end

  describe '.append_pid_to_journal' do
    let(:filename) { journal.pid_journal_filename('app') }

    it 'journals the pid and its process group' do
      expect(::Process).to receive(:getpgid).with(42).and_return(40)
      journal.append_pid_to_journal('app', 42)
      expect(::Process).to receive(:getpgid).with(42).and_return(40)
      expect(logger).to receive(:debug).with('Skipping duplicate pid 42 already in journal app')
      journal.append_pid_to_journal('app', 42)
      expect(File.read(filename)).to eq "42\n"
      expect(File.read(journal.pgid_journal_filename('app'))).to eq "40\n"
    end

    it 'ignores missing processes when looking up the process group' do
      expect(::Process).to receive(:getpgid).with(42).and_raise(Errno::ESRCH)
      journal.append_pid_to_journal('app', 42)
      expect(File.read(filename)).to eq "42\n"
      expect(File.exist?(journal.pgid_journal_filename('app'))).to be false
    end

    it 'skips invalid pids' do
      expect(::Process).to receive(:getpgid).with(1).and_return(1)
      expect(logger).to receive(:debug).with(/\ASkipping invalid pgid 1 /)
      expect(logger).to receive(:debug).with(/\ASkipping invalid pid 1 /)
      journal.append_pid_to_journal('app', 1)
      expect(File.exist?(filename)).to be false
    end
  end
end
