# frozen_string_literal: true

describe Bluepill::Socket do
  let(:base_dir) { "/var/run/bluepill" }
  let(:socket_path) { "/var/run/bluepill/socks/app.sock" }
  let(:socket) { instance_double(UNIXSocket, puts: nil) }

  describe ".socket_path" do
    it "is in the socks directory of the base directory" do
      expect(described_class.socket_path(base_dir, "app")).to eq(socket_path)
    end
  end

  describe ".client" do
    it "opens a UNIX socket and yields it" do
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      yielded = nil
      described_class.client(base_dir, "app") { |s| yielded = s }
      expect(yielded).to be(socket)
    end
  end

  describe ".client_command" do
    let(:printed) { [] }

    before do
      allow(Timeout).to receive(:timeout).with(Bluepill::Socket::TIMEOUT).and_yield
      allow(UNIXSocket).to receive(:open).with(socket_path).and_yield(socket)
      allow(described_class).to receive(:puts) { |line| printed << line }
    end

    def client_command = described_class.client_command(base_dir, "app", "status")

    context "when the daemon answers" do
      before { allow(socket).to receive(:read).and_return(Marshal.dump(%w[ok])) }

      it "returns the response" do
        expect(client_command).to eq(%w[ok])
      end

      it "sends the command" do
        client_command
        expect(socket).to have_received(:puts).with("status")
      end

      it "waits for the answer once, for at most TIMEOUT" do
        client_command
        expect(Timeout).to have_received(:timeout).with(Bluepill::Socket::TIMEOUT).once
      end

      it "connects once" do
        client_command
        expect(UNIXSocket).to have_received(:open).once
      end

      it "does not retry" do
        client_command
        expect(printed).to eq([])
      end
    end

    context "when the daemon times out twice" do
      before do
        calls = 0
        allow(socket).to receive(:read) do
          calls += 1
          raise Timeout::Error if calls < 3

          Marshal.dump("done")
        end
      end

      it "returns the response" do
        expect(client_command).to eq("done")
      end

      it "says it retries" do
        client_command
        expect(printed).to eq(["Retry 1 of 5", "Retry 2 of 5"])
      end
    end

    context "when the daemon never answers" do
      before do
        allow(socket).to receive(:read).and_raise(EOFError)
      end

      def client_command_until_giving_up
        client_command
      rescue Bluepill::ConnectionError
        nil
      end

      it "gives up with a ConnectionError" do
        timed_out = having_attributes(message: "Socket Timeout: Server may not be responding", exit_status: 1)
        expect { client_command }.to raise_error(an_instance_of(Bluepill::ConnectionError).and(timed_out))
      end

      it "tries MAX_ATTEMPTS times" do
        client_command_until_giving_up
        expect(UNIXSocket).to have_received(:open).exactly(Bluepill::Socket::MAX_ATTEMPTS).times
      end

      it "says it retries after each attempt but the last" do
        client_command_until_giving_up
        expect(printed).to eq(["Retry 1 of 5", "Retry 2 of 5", "Retry 3 of 5", "Retry 4 of 5"])
      end
    end
  end

  describe ".server" do
    let(:server) { instance_double(UNIXServer) }

    it "opens a UNIX server socket" do
      allow(UNIXServer).to receive(:open).with(socket_path).and_return(server)
      expect(described_class.server(base_dir, "app")).to be(server)
    end

    context "when the socket file already exists" do
      before do
        calls = 0
        allow(UNIXServer).to receive(:open).with(socket_path) do
          calls += 1
          raise Errno::EADDRINUSE if calls == 1

          server
        end
        allow(File).to receive(:delete)
      end

      it "replaces a stale socket file" do
        allow(UNIXSocket).to receive(:open).with(socket_path).and_raise(Errno::ECONNREFUSED)
        expect(described_class.server(base_dir, "app")).to be(server)
      end

      it "deletes a stale socket file" do
        allow(UNIXSocket).to receive(:open).with(socket_path).and_raise(Errno::ECONNREFUSED)
        described_class.server(base_dir, "app")
        expect(File).to have_received(:delete).with(socket_path)
      end

      it "raises when another server is listening" do
        allow(UNIXSocket).to receive(:open).with(socket_path).and_return(socket)
        running = having_attributes(message: "Server is already running!", exit_status: 7)
        expect { described_class.server(base_dir, "app") }.to raise_error(
          an_instance_of(Bluepill::AlreadyRunningError).and(running)
        )
      end
    end
  end
end
