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
        @open_timeout = options[:open_timeout] || options[:timeout] || 5
        @read_timeout = options[:read_timeout] || options[:timeout] || 5
      end

      def run(pid)
        session = Net::HTTP.new(@uri.host, @uri.port)
        session.open_timeout = @open_timeout
        session.read_timeout = @read_timeout
        session.start do |http|
          http.get(@uri.path)
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
    end
  end
end