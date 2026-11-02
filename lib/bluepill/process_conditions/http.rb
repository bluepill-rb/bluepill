require "net/http"
require "uri"

module Bluepill
  module ProcessConditions
    # Checks that a URL answers as expected
    #
    # A config names it `checks :http`, with url: the URL to get, kind: the
    # response it should be (a Net::HTTP class name such as :success or
    # :ok, or a status code such as 200, :success by default), pattern: a
    # Regexp its body should match, and timeout: (or open_timeout: and
    # read_timeout:) in seconds, 5 by default.
    #
    # @example
    #   process.checks :http, url: 'http://localhost:4567/', kind: :success, pattern: /html/, timeout: 3.seconds
    #
    # @api private
    class Http < ProcessCondition
      # Create the check
      #
      # @param [Hash{Symbol => Object}] options the check's options, with
      #   :url, :kind, :pattern, :timeout, :open_timeout and :read_timeout
      #
      # @return [void]
      #
      # @raise [KeyError] for a numeric kind that isn't an HTTP status
      #
      # @raise [NameError] for a kind that names no Net::HTTP response
      #
      # @api private
      def initialize(options = {})
        super
        @uri = URI.parse(options[:url]) #: URI::HTTP
        @kind = response_class(options[:kind])
        @pattern = options[:pattern]
        @open_timeout = (options[:open_timeout] || options[:timeout] || 5).to_i
        @read_timeout = (options[:read_timeout] || options[:timeout] || 5).to_i
      end

      # Get the URL
      #
      # HTTPS is checked without verifying the certificate.
      #
      # @param [Integer, nil] _pid the process's pid
      # @param [Boolean] _include_children whether to include its children
      #
      # @return [Net::HTTPResponse, StandardError] the response, or the error
      #   that stopped the request
      #
      # @api private
      def run(_pid, _include_children)
        session = new_session
        hide_net_http_bug do
          session.start do |http|
            http.get(@uri.request_uri)
          end
        end
      rescue => e
        e
      end

      # Return whether the response is the expected kind, and matches
      #
      # @param [Net::HTTPResponse, StandardError] value what run read
      #
      # @return [Boolean] true when the response is the kind the check
      #   expects, and its body matches the pattern if the check has one
      #
      # @api private
      def check?(value)
        return false unless value.is_a?(@kind)
        return true unless @pattern

        response = value #: Net::HTTPResponse
        !(@pattern =~ response.body).nil?
      end

      private

      # Return the Net::HTTPResponse class of a kind of response
      #
      # @param [Integer, String, Symbol, nil] kind a status code, such as
      #   200, or a Net::HTTP class name, such as :success or :ok
      #
      # @return [Class] the response class, Net::HTTPSuccess when there's no
      #   kind
      #
      # @raise [KeyError] for a numeric kind that isn't an HTTP status
      #
      # @raise [NameError] for a kind that names no Net::HTTP response
      #
      # @api private
      def response_class(kind)
        case kind
        when Integer
          Net::HTTPResponse::CODE_TO_OBJ.fetch(kind.to_s)
        when String, Symbol
          Net.const_get("HTTP#{Util.camelize(kind)}")
        else
          Net::HTTPSuccess
        end
      end

      # Return a session with the URL's host, set up to get the URL
      #
      # HTTPS is checked without verifying the certificate.
      #
      # @return [Net::HTTP] the session, not started yet
      #
      # @api private
      def new_session
        host = @uri.host #: String
        session = Net::HTTP.new(host, @uri.port)
        if @uri.scheme.eql?("https")
          require "net/https"
          session.use_ssl = true
          session.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        session.open_timeout = @open_timeout
        session.read_timeout = @read_timeout
        session
      end

      # Run the block, raising a refused connection as one
      #
      # Net::HTTP raises NoMethodError (closed? for nil) when it can't
      # connect, so this raises Errno::ECONNREFUSED instead.
      #
      # @yield the request
      # @yieldreturn [Object] the response
      #
      # @return [Object] what the block returns
      #
      # @raise [Errno::ECONNREFUSED] when the connection was refused
      #
      # @api private
      def hide_net_http_bug
        yield
      rescue NoMethodError => e
        # Ruby 3.4 changed the wording of this error
        message = e.to_s
        raise(Errno::ECONNREFUSED, "Connection refused attempting to contact #{@uri.scheme}://#{@uri.host}:#{@uri.port}") if message.include?("undefined method `closed?' for nil:NilClass") || message.include?("undefined method 'closed?' for nil")

        raise
      end
    end
  end
end
