describe Bluepill::Application do
  let(:app) { described_class.new("test", base_dir: "/var/bluepill") }
  let(:traps) { {} }

  before do
    logger = instance_double(Bluepill::Logger)
    allow(logger).to receive(:prefix_with).and_return(logger)
    allow(Bluepill::Logger).to receive(:new).and_return(logger)
    allow(Bluepill::ProcessJournal).to receive(:setup)
    allow(Bluepill::ProcessJournal).to receive(:logger=)
    allow(Signal).to receive(:trap) { |signal, &block| traps[signal] = block }
    # Don't make /var/bluepill's directories
    allow(FileUtils).to receive_messages(mkdir_p: nil, chmod: nil)
  end

  def mutex_locked?
    app.instance_variable_get(:@mutex).locked?
  end

  def pid_file
    "/var/bluepill/pids/test.pid"
  end

  describe "run" do
    let(:group) { instance_double(Bluepill::Group) }
    let(:other_group) { instance_double(Bluepill::Group) }
    let(:calls) { [] }

    before do
      app.groups = {"web" => group, "db" => other_group}
      allow($stdout).to receive(:puts)
      # The TERM trap cleans up
      allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks)
      allow(Bluepill::System).to receive(:delete_if_exists)
      allow(Bluepill::System).to receive(:reset_data) { calls << [:reset_data, mutex_locked?] }
      allow(group).to receive(:tick) { calls << [:web, mutex_locked?] }
      allow(other_group).to receive(:tick) { calls << [:db, mutex_locked?] }
      allow(Kernel).to receive(:sleep).with(1) do
        calls << [:sleep, mutex_locked?]
        traps["TERM"].call(15) if calls.collect(&:first).count(:sleep) == 2
      end
      app.send(:run)
    end

    it "ticks every group each second until terminated" do
      expect(calls.collect(&:first)).to eq([:reset_data, :web, :db, :sleep, :reset_data, :web, :db, :sleep])
    end

    it "ticks while holding the mutex, and sleeps without it" do
      expect(calls.first(4)).to eq([[:reset_data, true], [:web, true], [:db, true], [:sleep, false]])
    end
  end

  describe "cleanup" do
    let(:socket) { instance_double(UNIXServer, path: "/var/bluepill/test.sock") }

    before do
      allow(Bluepill::ProcessJournal).to receive(:clear_all_atomic_fs_locks)
      allow(Bluepill::System).to receive(:delete_if_exists)
    end

    it "clears the journal locks" do
      app.send(:cleanup)
      expect(Bluepill::ProcessJournal).to have_received(:clear_all_atomic_fs_locks)
    end

    it "deletes the pid file" do
      app.send(:cleanup)
      expect(Bluepill::System).to have_received(:delete_if_exists).with(pid_file)
    end

    it "deletes the socket" do
      app.socket = socket
      app.send(:cleanup)
      expect(Bluepill::System).to have_received(:delete_if_exists).with(socket.path)
    end

    it "deletes only the pid file without a socket" do
      app.send(:cleanup)
      expect(Bluepill::System).to have_received(:delete_if_exists).once
    end

    it "ignores a closed socket" do
      allow(socket).to receive(:path).and_raise(IOError)
      app.socket = socket
      app.send(:cleanup)
      expect(Bluepill::System).to have_received(:delete_if_exists).once
    end
  end
end
