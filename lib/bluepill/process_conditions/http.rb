require 'net/http'
require 'uri'

module Bluepill
  module ProcessConditions
    class Http < ProcessCondition
      def initialize(options = {})
        @uri = URI.parse(options[:url])
        @kind = case options[:kind]
                  when Fixnum then Net::HTTPResponse::CODE_TO_OBJ[options[:kind].to_s]
                  when String, Symbol then "Net::HTTP#{options[:kind].to_s.camelize}".constantize
                else
                  Net::HTTPSuccess
                end
        @pattern = options[:pattern] || nil
        @open_timeout = (options[:open_timeout] || options[:timeout] || 5).to_i
        @read_timeout = (options[:read_timeout] || options[:timeout] || 5).to_i
      end

      def run(pid)
        session = Net::HTTP.new(@uri.host, @uri.port)
        session.open_timeout = @open_timeout
        session.read_timeout = @read_timeout
        hide_net_http_bug do
          session.start do |http|
            http.get(@uri.path)
          end
        end
      rescue
        $!
      end

      def check(value)
        return false unless value.kind_of?(@kind)
        return true  unless @pattern
        return false unless value.class.body_permitted?
        @pattern === value.body
      end

    private
      def hide_net_http_bug
        yield
      rescue NoMethodError => e
        if e.to_s =~ /#{Regexp.escape(%q|undefined method `closed?' for nil:NilClass|)}/
          raise Errno::ECONNREFUSED, "Connection refused attempting to contact #{@uri.scheme}://#{@uri.host}:#{@uri.port}"
        else
          raise
        end
      end
    end
  end
end