describe Bluepill::ProcessConditions::Http do
  def http(options = {})
    Bluepill::ProcessConditions::Http.new({url: 'http://example.com:8080/status?full=1'}.merge(options))
  end

  def response(klass, code, body = nil)
    res = klass.new('1.1', code, 'message')
    allow(res).to receive(:body).and_return(body)
    res
  end

  describe '#initialize' do
    it 'warns, once for each url, that 0.3.0 verifies an https certificate' do
      warning = 'DEPRECATION: bluepill 0.3.0 verifies the TLS certificate of the http check of https://example.com/, ' \
                "where 0.1 and 0.2 don't. Add verify_ssl: true to verify it now, or verify_ssl: false to keep checking a self-signed one.\n"
      expect { http(url: 'https://example.com/') }.to output(warning).to_stderr
      expect { http(url: 'https://example.com/') }.not_to output.to_stderr
      expect { http(url: 'https://example.com/other') }.to output(%r{check of https://example.com/other,}).to_stderr
    end

    it 'does not warn about an https url that sets verify_ssl' do
      expect { http(url: 'https://example.com/', verify_ssl: false) }.not_to output.to_stderr
      expect { http(url: 'https://example.com/', verify_ssl: true) }.not_to output.to_stderr
    end

    it 'verifies the certificate only with verify_ssl: true' do
      expect(http(verify_ssl: true).instance_variable_get(:@verify_ssl)).to be(true)
      expect(http(verify_ssl: false).instance_variable_get(:@verify_ssl)).to be(false)
      expect(http.instance_variable_get(:@verify_ssl)).to be_nil
    end

    it 'does not warn about an http url' do
      expect { http }.not_to output.to_stderr
    end

    it 'requires a url' do
      expect { Bluepill::ProcessConditions::Http.new }.to raise_error(URI::InvalidURIError)
    end

    it 'stores its options' do
      expect(http.instance_variable_get(:@options)).to eq(url: 'http://example.com:8080/status?full=1')
    end

    it 'parses the url' do
      expect(http.instance_variable_get(:@uri)).to eq(URI.parse('http://example.com:8080/status?full=1'))
    end

    it 'has no pattern by default' do
      expect(http.instance_variable_get(:@pattern)).to be_nil
    end

    it 'accepts a pattern' do
      expect(http(pattern: /ok/).instance_variable_get(:@pattern)).to eq(/ok/)
    end

    it 'expects a successful response by default' do
      expect(http.instance_variable_get(:@kind)).to eq(Net::HTTPSuccess)
    end

    it 'accepts a status code as kind' do
      expect(http(kind: 200).instance_variable_get(:@kind)).to eq(Net::HTTPOK)
    end

    it 'rejects an unknown status code' do
      expect { http(kind: 999) }.to raise_error(KeyError)
    end

    it 'accepts a string as kind' do
      expect(http(kind: 'redirection').instance_variable_get(:@kind)).to eq(Net::HTTPRedirection)
    end

    it 'accepts a symbol as kind' do
      expect(http(kind: :not_found).instance_variable_get(:@kind)).to eq(Net::HTTPNotFound)
    end

    it 'uses a default timeout of 5 seconds' do
      condition = http
      expect(condition.instance_variable_get(:@open_timeout)).to eq(5)
      expect(condition.instance_variable_get(:@read_timeout)).to eq(5)
    end

    it 'accepts a timeout' do
      condition = http(timeout: 10)
      expect(condition.instance_variable_get(:@open_timeout)).to eq(10)
      expect(condition.instance_variable_get(:@read_timeout)).to eq(10)
    end

    it 'accepts separate open and read timeouts' do
      condition = http(timeout: 10, open_timeout: 2, read_timeout: 3.5)
      expect(condition.instance_variable_get(:@open_timeout)).to eq(2)
      expect(condition.instance_variable_get(:@read_timeout)).to eq(3)
    end

    it 'accepts timeouts as strings' do
      condition = http(open_timeout: '2.5', read_timeout: '3.5')
      expect(condition.instance_variable_get(:@open_timeout)).to eq(2)
      expect(condition.instance_variable_get(:@read_timeout)).to eq(3)
    end
  end

  describe '#run' do
    let(:session) { instance_double(Net::HTTP, :open_timeout= => nil, :read_timeout= => nil) }
    let(:connection) { instance_double(Net::HTTP) }
    let(:ok) { response(Net::HTTPOK, '200') }

    before do
      allow(session).to receive(:start).and_yield(connection)
      allow(connection).to receive(:get).with('/status?full=1').and_return(ok)
    end

    it 'requests the url over http' do
      expect(Net::HTTP).to receive(:new).with('example.com', 8080).and_return(session)
      expect(http(open_timeout: 1, read_timeout: 2).run(123, false)).to eq(ok)
      expect(session).to have_received(:open_timeout=).with(1)
      expect(session).to have_received(:read_timeout=).with(2)
    end

    it 'requests the url over https without verifying the certificate by default' do
      condition = nil
      expect { condition = http(url: 'https://example.com/status?full=1') }.to output(/DEPRECATION/).to_stderr
      allow(condition).to receive(:require).and_call_original
      allow(session).to receive(:use_ssl=)
      allow(session).to receive(:verify_mode=)
      expect(Net::HTTP).to receive(:new).with('example.com', 443).and_return(session)
      expect(condition.run(123, false)).to eq(ok)
      expect(condition).to have_received(:require).with('net/https')
      expect(session).to have_received(:use_ssl=).with(true)
      expect(session).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
    end

    it 'requests the url over https without verifying the certificate with verify_ssl: false' do
      condition = http(url: 'https://example.com/status?full=1', verify_ssl: false)
      allow(session).to receive(:use_ssl=)
      allow(session).to receive(:verify_mode=)
      expect(Net::HTTP).to receive(:new).with('example.com', 443).and_return(session)
      expect(condition.run(123, false)).to eq(ok)
      expect(session).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
    end

    it 'verifies the certificate with verify_ssl: true' do
      condition = http(url: 'https://example.com/status?full=1', verify_ssl: true)
      allow(session).to receive(:use_ssl=)
      allow(session).to receive(:verify_mode=)
      expect(Net::HTTP).to receive(:new).with('example.com', 443).and_return(session)
      expect(condition.run(123, false)).to eq(ok)
      expect(session).to have_received(:use_ssl=).with(true)
      expect(session).to have_received(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    end

    context 'when the request fails' do
      before do
        allow(Net::HTTP).to receive(:new).and_return(session)
      end

      it 'returns the error' do
        error = Errno::ETIMEDOUT.new
        allow(session).to receive(:start).and_raise(error)
        expect(http.run(123, false)).to eq(error)
      end

      it 'turns the Net::HTTP closed? bug into a connection refused error before Ruby 3.4' do
        allow(session).to receive(:start).and_raise(NoMethodError.new("undefined method `closed?' for nil:NilClass"))
        error = http.run(123, false)
        expect(error).to be_a(Errno::ECONNREFUSED)
        expect(error.message).to eq('Connection refused - Connection refused attempting to contact http://example.com:8080')
      end

      it 'turns the Net::HTTP closed? bug into a connection refused error on Ruby 3.4 and newer' do
        allow(session).to receive(:start).and_raise(NoMethodError.new("undefined method 'closed?' for nil"))
        error = http.run(123, false)
        expect(error).to be_a(Errno::ECONNREFUSED)
        expect(error.message).to eq('Connection refused - Connection refused attempting to contact http://example.com:8080')
      end

      it 'finds the Net::HTTP closed? bug anywhere in the message' do
        message = "private method: undefined method `closed?' for nil:NilClass (NoMethodError)"
        allow(session).to receive(:start).and_raise(NoMethodError.new(message))
        expect(http.run(123, false)).to be_a(Errno::ECONNREFUSED)
      end

      it 'finds the Ruby 3.4 wording of the Net::HTTP closed? bug anywhere in the message' do
        message = "private method: undefined method 'closed?' for nil (NoMethodError)"
        allow(session).to receive(:start).and_raise(NoMethodError.new(message))
        expect(http.run(123, false)).to be_a(Errno::ECONNREFUSED)
      end

      it 'returns other NoMethodErrors' do
        error = NoMethodError.new('undefined method `foo\' for nil:NilClass')
        allow(session).to receive(:start).and_raise(error)
        expect(http.run(123, false)).to eq(error)
      end

      it 'returns other NoMethodErrors in the Ruby 3.4 wording' do
        error = NoMethodError.new("undefined method 'foo' for nil")
        allow(session).to receive(:start).and_raise(error)
        expect(http.run(123, false)).to eq(error)
      end
    end
  end

  describe '#check' do
    it 'fails when the response is not of the expected kind' do
      expect(http.check(response(Net::HTTPNotFound, '404', 'ok'))).to be false
    end

    it 'fails when the request raised an error' do
      expect(http.check(Errno::ECONNREFUSED.new)).to be false
    end

    it 'passes when the response is of the expected kind and there is no pattern' do
      expect(http.check(response(Net::HTTPOK, '200'))).to be true
    end

    it 'fails when a pattern is given and the response has no body' do
      expect(http(pattern: /ok/).check(response(Net::HTTPNoContent, '204'))).to be false
    end

    it 'passes when the body matches the pattern' do
      expect(http(pattern: /ok/).check(response(Net::HTTPOK, '200', 'all ok'))).to be_truthy
    end

    it 'fails when the body does not match the pattern' do
      expect(http(pattern: /ok/).check(response(Net::HTTPOK, '200', 'down'))).to be_falsey
    end
  end
end
