describe Bluepill::Socket do
  let(:base_dir) { '/var/run/bluepill' }
  let(:socket_path) { '/var/run/bluepill/socks/app.sock' }
  let(:socket) { double('socket', puts: nil) }

  describe '.socket_path' do
    it 'should be in the socks directory of the base directory' do
      expect(Bluepill::Socket.socket_path(base_dir, 'app')).to eq(socket_path)
    end
  end

  describe '.client' do
    it 'should open a UNIX socket and yield it' do
      expect(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      yielded = nil
      Bluepill::Socket.client(base_dir, 'app') { |s| yielded = s }
      expect(yielded).to be(socket)
    end
  end

  describe '.client_command' do
    before(:each) do
      allow(Timeout).to receive(:timeout).with(Bluepill::Socket::TIMEOUT).and_yield
      allow(Bluepill::Socket).to receive(:puts)
      allow(Bluepill::Socket).to receive(:abort)
    end

    it 'should send the command and return the response' do
      allow(socket).to receive(:read).and_return(Marshal.dump(%w[ok]))
      expect(UNIXSocket).to receive(:open).with(socket_path).once.and_yield(socket)
      expect(Bluepill::Socket.client_command(base_dir, 'app', 'status')).to eq(%w[ok])
      expect(socket).to have_received(:puts).with('status')
      expect(Timeout).to have_received(:timeout).with(Bluepill::Socket::TIMEOUT).once
      expect(Bluepill::Socket).not_to have_received(:puts)
    end

    it 'should retry after a timeout' do
      calls = 0
      allow(socket).to receive(:read) do
        calls += 1
        raise Timeout::Error if calls < 3

        Marshal.dump('done')
      end
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      expect(Bluepill::Socket.client_command(base_dir, 'app', 'status')).to eq('done')
      expect(Bluepill::Socket).to have_received(:puts).with('Retry 1 of 5').ordered
      expect(Bluepill::Socket).to have_received(:puts).with('Retry 2 of 5').ordered
      expect(Bluepill::Socket).to have_received(:puts).twice
      expect(Bluepill::Socket).not_to have_received(:abort)
    end

    it 'should abort after the maximum number of attempts' do
      allow(socket).to receive(:read).and_raise(EOFError)
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      allow(Bluepill::Socket).to receive(:abort).and_raise(SystemExit)
      expect { Bluepill::Socket.client_command(base_dir, 'app', 'status') }.to raise_error(SystemExit)
      expect(UNIXSocket).to have_received(:open).exactly(Bluepill::Socket::MAX_ATTEMPTS).times
      expect(Bluepill::Socket).to have_received(:puts).exactly(Bluepill::Socket::MAX_ATTEMPTS - 1).times
      expect(Bluepill::Socket).to have_received(:abort).with('Socket Timeout: Server may not be responding').once
    end
  end

  describe '.server' do
    let(:server) { double('server') }

    it 'should open a UNIX server socket' do
      expect(UNIXServer).to receive(:open).with(socket_path).and_return(server)
      expect(Bluepill::Socket.server(base_dir, 'app')).to be(server)
    end

    context 'when the socket file already exists' do
      before(:each) do
        calls = 0
        allow(UNIXServer).to receive(:open).with(socket_path) do
          calls += 1
          raise Errno::EADDRINUSE if calls == 1

          server
        end
      end

      it 'should replace a stale socket file' do
        expect(UNIXSocket).to receive(:open).with(socket_path).and_raise(Errno::ECONNREFUSED)
        expect(File).to receive(:delete).with(socket_path)
        expect(Bluepill::Socket.server(base_dir, 'app')).to be(server)
      end

      context 'and another server is listening' do
        before(:each) do
          allow(UNIXSocket).to receive(:open).with(socket_path).and_return(socket)
        end

        it 'should print an error and exit' do
          expect($stderr).to receive(:puts).with('Server is already running!')
          expect(Bluepill::Socket).to receive(:exit).with(7)
          Bluepill::Socket.server(base_dir, 'app')
        end
      end
    end
  end
end
