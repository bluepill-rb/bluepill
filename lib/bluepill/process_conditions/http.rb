require 'net/http'
require 'uri'

module Bluepill
  module ProcessConditions
    class Http < ProcessCondition
      def initialize(options = {})
        super
        @uri = URI.parse(options[:url]) #: URI::HTTP
        @kind = case options[:kind]
                when Integer
                  Net::HTTPResponse::CODE_TO_OBJ[options.fetch(:kind).to_s]
                when String, Symbol
                  Net.const_get("HTTP#{options.fetch(:kind).to_s.camelize}")
                else
                  Net::HTTPSuccess
                end

        @pattern = options[:pattern]
        @open_timeout = (options[:open_timeout] || options[:timeout] || 5).to_i
        @read_timeout = (options[:read_timeout] || options[:timeout] || 5).to_i
      end

      def run(_pid, _include_children)
        host = @uri.host #: String
        session = Net::HTTP.new(host, @uri.port)
        if @uri.scheme.eql?('https')
          require 'net/https'
          session.use_ssl = true
          session.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        session.open_timeout = @open_timeout
        session.read_timeout = @read_timeout
        hide_net_http_bug do
          session.start do |http|
            http.get(@uri.request_uri)
          end
        end
      rescue StandardError => e
        e
      end

      def check(value)
        return false unless value.is_a?(@kind)
        return true  unless @pattern

        response = value #: Net::HTTPResponse
        !(@pattern =~ response.body).nil?
      end

    private

      def hide_net_http_bug
        yield
      rescue NoMethodError => e
        raise(Errno::ECONNREFUSED, "Connection refused attempting to contact #{@uri.scheme}://#{@uri.host}:#{@uri.port}") if e.to_s.include?("undefined method `closed?' for nil:NilClass")

        raise
      end
    end
  end
end
