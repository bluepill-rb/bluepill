# frozen_string_literal: true

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
      # @param [String] url the URL to get
      # @param [Integer, String, Symbol, nil] kind the response it expects,
      #   as a status code, such as 200, or a Net::HTTP class name, such as
      #   :success, the default
      # @param [Regexp, nil] pattern what the body must match, if anything
      # @param [Numeric, String] timeout the seconds to wait to connect and
      #   to read, unless open_timeout or read_timeout is given
      # @param [Numeric, String] open_timeout the seconds to wait to connect
      # @param [Numeric, String] read_timeout the seconds to wait to read
      # @param [Hash{Symbol => Object}] options the check's other options
      #
      # @return [void]
      #
      # @raise [KeyError] for a numeric kind that isn't an HTTP status
      #
      # @raise [NameError] for a kind that names no Net::HTTP response
      #
      # @api private
      def initialize(url:, kind: nil, pattern: nil, timeout: 5, open_timeout: timeout, read_timeout: timeout, **options)
        super(**options)
        @uri = URI.parse(url) #: URI::HTTP
        @kind = response_class(kind)
        @pattern = pattern
        @open_timeout = open_timeout.to_i
        @read_timeout = read_timeout.to_i
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
        new_session.start { |http| http.get(@uri.request_uri) }
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

        pattern = @pattern
        return true unless pattern

        response = value #: Net::HTTPResponse
        pattern.match?(response.body)
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
    end
  end
end
