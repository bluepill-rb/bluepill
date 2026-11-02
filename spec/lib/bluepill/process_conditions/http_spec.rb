# frozen_string_literal: true

describe Bluepill::ProcessConditions::Http do
  def http(**options)
    Bluepill::ProcessConditions::Http.new(url: "http://example.com:8080/status?full=1", **options)
  end

  def timeouts(condition)
    [condition.instance_variable_get(:@open_timeout), condition.instance_variable_get(:@read_timeout)]
  end

  def response(klass, code, body = nil)
    res = klass.new("1.1", code, "message")
    allow(res).to receive(:body).and_return(body)
    res
  end

  describe "#initialize" do
    it "requires a url" do
      expect { described_class.new }.to raise_error(ArgumentError, /missing keywords?: :?url/)
    end

    it "rejects an option it doesn't take" do
      expect { http(note: "x") }.to raise_error(ArgumentError, /unknown keyword: :note/)
    end

    it "parses the url" do
      expect(http.instance_variable_get(:@uri)).to eq(URI.parse("http://example.com:8080/status?full=1"))
    end

    it "has no pattern by default" do
      expect(http.instance_variable_get(:@pattern)).to be_nil
    end

    it "accepts a pattern" do
      expect(http(pattern: /ok/).instance_variable_get(:@pattern)).to eq(/ok/)
    end

    it "expects a successful response by default" do
      expect(http.instance_variable_get(:@kind)).to eq(Net::HTTPSuccess)
    end

    it "accepts a status code as kind" do
      expect(http(kind: 200).instance_variable_get(:@kind)).to eq(Net::HTTPOK)
    end

    it "rejects an unknown status code" do
      expect { http(kind: 999) }.to raise_error(KeyError)
    end

    it "accepts a string as kind" do
      expect(http(kind: "redirection").instance_variable_get(:@kind)).to eq(Net::HTTPRedirection)
    end

    it "accepts a symbol as kind" do
      expect(http(kind: :not_found).instance_variable_get(:@kind)).to eq(Net::HTTPNotFound)
    end

    it "uses a default timeout of 5 seconds" do
      expect(timeouts(http)).to eq([5, 5])
    end

    it "accepts a timeout" do
      expect(timeouts(http(timeout: 10))).to eq([10, 10])
    end

    it "accepts separate open and read timeouts" do
      expect(timeouts(http(timeout: 10, open_timeout: 2, read_timeout: 3.5))).to eq([2, 3])
    end

    it "accepts timeouts as strings" do
      expect(timeouts(http(open_timeout: "2.5", read_timeout: "3.5"))).to eq([2, 3])
    end
  end

  describe "#run" do
    let(:session) { instance_double(Net::HTTP, :open_timeout= => nil, :read_timeout= => nil) }
    let(:connection) { instance_double(Net::HTTP) }
    let(:ok) { response(Net::HTTPOK, "200") }

    before do
      allow(session).to receive(:start).and_yield(connection)
      allow(connection).to receive(:get).with("/status?full=1").and_return(ok)
    end

    context "with an http url" do
      before do
        allow(Net::HTTP).to receive(:new).with("example.com", 8080).and_return(session)
      end

      it "returns the response" do
        expect(http.run(123, false)).to eq(ok)
      end

      it "sets the open timeout" do
        http(open_timeout: 1, read_timeout: 2).run(123, false)
        expect(session).to have_received(:open_timeout=).with(1)
      end

      it "sets the read timeout" do
        http(open_timeout: 1, read_timeout: 2).run(123, false)
        expect(session).to have_received(:read_timeout=).with(2)
      end
    end

    context "with an https url" do
      let(:https) { http(url: "https://example.com/status?full=1") }

      before do
        allow(https).to receive(:require).and_call_original
        allow(session).to receive(:use_ssl=)
        allow(session).to receive(:verify_mode=)
        allow(Net::HTTP).to receive(:new).with("example.com", 443).and_return(session)
      end

      it "returns the response" do
        expect(https.run(123, false)).to eq(ok)
      end

      it "loads net/https" do
        https.run(123, false)
        expect(https).to have_received(:require).with("net/https")
      end

      it "uses ssl" do
        https.run(123, false)
        expect(session).to have_received(:use_ssl=).with(true)
      end

      it "does not verify the certificate" do
        https.run(123, false)
        expect(session).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
      end
    end

    context "when the request fails" do
      before do
        allow(Net::HTTP).to receive(:new).and_return(session)
      end

      it "returns the error" do
        error = Errno::ETIMEDOUT.new
        allow(session).to receive(:start).and_raise(error)
        expect(http.run(123, false)).to eq(error)
      end
    end
  end

  describe "#run without a server" do
    # A port nothing listens on, from a server that's closed again
    let(:port) do
      server = TCPServer.new("127.0.0.1", 0)
      server.addr[1].tap { server.close }
    end

    it "returns a refused connection as the error Net::HTTP raises" do
      expect(http(url: "http://127.0.0.1:#{port}/").run(123, false)).to be_a(Errno::ECONNREFUSED)
    end
  end

  describe "#check?" do
    it "fails when the response is not of the expected kind" do
      expect(http.check?(response(Net::HTTPNotFound, "404", "ok"))).to be false
    end

    it "fails when the request raised an error" do
      expect(http.check?(Errno::ECONNREFUSED.new)).to be false
    end

    it "passes when the response is of the expected kind and there is no pattern" do
      expect(http.check?(response(Net::HTTPOK, "200"))).to be true
    end

    it "fails when a pattern is given and the response has no body" do
      expect(http(pattern: /ok/).check?(response(Net::HTTPNoContent, "204"))).to be false
    end

    it "passes when the body matches the pattern" do
      expect(http(pattern: /ok/)).to be_check(response(Net::HTTPOK, "200", "all ok"))
    end

    it "fails when the body does not match the pattern" do
      expect(http(pattern: /ok/)).not_to be_check(response(Net::HTTPOK, "200", "down"))
    end
  end
end
