describe Bluepill::Socket do
  let(:base_dir) { '/var/run/bluepill' }
  let(:socket_path) { '/var/run/bluepill/socks/app.sock' }
  let(:socket) { instance_double(UNIXSocket, puts: nil) }

  describe '.socket_path' do
    it 'is in the socks directory of the base directory' do
      expect(described_class.socket_path(base_dir, 'app')).to eq(socket_path)
    end
  end

  describe '.client' do
    it 'opens a UNIX socket and yields it' do
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      yielded = nil
      described_class.client(base_dir, 'app') { |s| yielded = s }
      expect(yielded).to be(socket)
    end
  end

  describe '.client_command' do
    before do
      allow(Timeout).to receive(:timeout).with(Bluepill::Socket::TIMEOUT).and_yield
      allow(described_class).to receive(:puts)
      allow(described_class).to receive(:abort)
    end

    it 'sends the command and returns the response' do
      allow(socket).to receive(:read).and_return(Marshal.dump(%w[ok]))
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      expect(described_class.client_command(base_dir, 'app', 'status')).to eq(%w[ok])
      expect(UNIXSocket).to have_received(:open).once
      expect(socket).to have_received(:puts).with('status')
      expect(Timeout).to have_received(:timeout).with(Bluepill::Socket::TIMEOUT).once
      expect(described_class).not_to have_received(:puts)
    end

    it 'retries after a timeout' do
      calls = 0
      allow(socket).to receive(:read) do
        calls += 1
        raise Timeout::Error if calls < 3

        Marshal.dump('done')
      end
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      expect(described_class.client_command(base_dir, 'app', 'status')).to eq('done')
      expect(described_class).to have_received(:puts).with('Retry 1 of 5').ordered
      expect(described_class).to have_received(:puts).with('Retry 2 of 5').ordered
      expect(described_class).to have_received(:puts).twice
      expect(described_class).not_to have_received(:abort)
    end

    it 'aborts after the maximum number of attempts' do
      allow(socket).to receive(:read).and_raise(EOFError)
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      allow(described_class).to receive(:abort).and_raise(SystemExit)
      expect { described_class.client_command(base_dir, 'app', 'status') }.to raise_error(SystemExit)
      expect(UNIXSocket).to have_received(:open).exactly(Bluepill::Socket::MAX_ATTEMPTS).times
      expect(described_class).to have_received(:puts).exactly(Bluepill::Socket::MAX_ATTEMPTS - 1).times
      expect(described_class).to have_received(:abort).with('Socket Timeout: Server may not be responding').once
    end
  end

  describe '.server' do
    let(:server) { instance_double(UNIXServer) }

    it 'opens a UNIX server socket' do
      allow(UNIXServer).to receive(:open).with(socket_path).and_return(server)
      expect(described_class.server(base_dir, 'app')).to be(server)
    end

    context 'when the socket file already exists' do
      before do
        calls = 0
        allow(UNIXServer).to receive(:open).with(socket_path) do
          calls += 1
          raise Errno::EADDRINUSE if calls == 1

          server
        end
      end

      it 'replaces a stale socket file' do
        allow(UNIXSocket).to receive(:open).with(socket_path).and_raise(Errno::ECONNREFUSED)
        allow(File).to receive(:delete)
        expect(described_class.server(base_dir, 'app')).to be(server)
        expect(File).to have_received(:delete).with(socket_path)
      end

      context 'when another server is listening' do
        before do
          allow(UNIXSocket).to receive(:open).with(socket_path).and_return(socket)
        end

        it 'prints an error and exit' do
          expect { described_class.server(base_dir, 'app') }.to raise_error(
            an_instance_of(SystemExit).and(having_attributes(status: 7))
          ).and output("Server is already running!\n").to_stderr
        end
      end
    end
  end
end
