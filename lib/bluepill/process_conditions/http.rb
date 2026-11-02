require 'net/http'
require 'uri'

module Bluepill
  module ProcessConditions
    # Checks that a URL answers as expected
    #
    # A config names it `checks :http`, with url: the URL to get, kind: the
    # response it should be (a Net::HTTP class name such as :success or
    # :ok, or a status code such as 200, :success by default), pattern: a
    # Regexp its body should match, and timeout: (or open_timeout: and
    # read_timeout:) in seconds, 5 by default. With verify_ssl: true, an
    # https URL's certificate must be valid. Bluepill 0.1 doesn't verify it
    # by default, but bluepill 0.3.0 does.
    #
    # @example
    #   process.checks :http, url: 'http://localhost:4567/', kind: :success, pattern: /html/, timeout: 3.seconds
    #
    # @example A server whose certificate must be valid
    #   process.checks :http, url: 'https://localhost:4443/', verify_ssl: true
    #
    # @api private
    class Http < ProcessCondition
      # Create the check
      #
      # @param [Hash{Symbol => Object}] options the check's options, with
      #   :url, :kind, :pattern, :timeout, :open_timeout, :read_timeout and
      #   :verify_ssl
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
        @kind = case options[:kind]
                when Integer
                  Net::HTTPResponse::CODE_TO_OBJ.fetch(options.fetch(:kind).to_s)
                when String, Symbol
                  Net.const_get("HTTP#{options.fetch(:kind).to_s.camelize}")
                else
                  Net::HTTPSuccess
                end

        @pattern = options[:pattern]
        @open_timeout = (options[:open_timeout] || options[:timeout] || 5).to_i
        @read_timeout = (options[:read_timeout] || options[:timeout] || 5).to_i
        @verify_ssl = options[:verify_ssl]
        warn_unverified unless options.key?(:verify_ssl)
      end

      # Get the URL
      #
      # HTTPS verifies the server's certificate only with verify_ssl.
      #
      # @param [Integer, nil] _pid the process's pid
      # @param [Boolean] _include_children whether to include its children
      #
      # @return [Net::HTTPResponse, StandardError] the response, or the error
      #   that stopped the request
      #
      # @api private
      def run(_pid, _include_children)
        host = @uri.host #: String
        session = Net::HTTP.new(host, @uri.port)
        if @uri.scheme.eql?('https')
          require 'net/https'
          session.use_ssl = true
          session.verify_mode = @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
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

      # Return whether the response is the expected kind, and matches
      #
      # @param [Net::HTTPResponse, StandardError] value what run read
      #
      # @return [Boolean] true when the response is the kind the check
      #   expects, and its body matches the pattern if the check has one
      #
      # @api private
      def check(value)
        return false unless value.is_a?(@kind)
        return true  unless @pattern

        response = value #: Net::HTTPResponse
        !(@pattern =~ response.body).nil?
      end

    private

      # Warn that bluepill 0.3.0 verifies an https URL's certificate
      #
      # It warns about a check of an https URL that doesn't set verify_ssl,
      # once for each URL.
      #
      # @return [void]
      #
      # @api private
      def warn_unverified
        return unless @uri.scheme.eql?('https')

        message = "bluepill 0.3.0 verifies the TLS certificate of the http check of #{@uri}, where 0.1 and 0.2 don't. " \
                  'Add verify_ssl: true to verify it now, or verify_ssl: false to keep checking a self-signed one.'
        # The message names the URL, so it's the key
        Deprecation.warn(message, message)
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
