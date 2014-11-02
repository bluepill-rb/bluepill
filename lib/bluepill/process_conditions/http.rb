require 'net/http'
require 'uri'

module Bluepill
  module ProcessConditions
    class Http < ProcessCondition
      def initialize(options = {})
        @uri = URI.parse(options[:url])
        @kind = case options[:kind]
                when Fixnum
                  Net::HTTPResponse::CODE_TO_OBJ[options[:kind].to_s]
                when String, Symbol
                  Net.const_get("HTTP#{options[:kind].to_s.camelize}")
                else
                  Net::HTTPSuccess
                end
        @pattern = options[:pattern] || nil
        @open_timeout = (options[:open_timeout] || options[:timeout] || 5).to_i
        @read_timeout = (options[:read_timeout] || options[:timeout] || 5).to_i
      end

      def run(_pid, _include_children)
        session = Net::HTTP.new(@uri.host, @uri.port)
        if @uri.scheme == 'https'
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
      rescue
        $ERROR_INFO
      end

      def check(value)
        return false unless value.is_a?(@kind)
        return true  unless @pattern
        return false unless value.class.body_permitted?
        @pattern === value.body
      end

    private

      def hide_net_http_bug
        yield
      rescue NoMethodError => e
        if e.to_s =~ /#{Regexp.escape("undefined method `closed?' for nil:NilClass")}/
          raise(Errno::ECONNREFUSED.new("Connection refused attempting to contact #{@uri.scheme}://#{@uri.host}:#{@uri.port}"))
        else
          raise
        end
      end
    end
  end
end
