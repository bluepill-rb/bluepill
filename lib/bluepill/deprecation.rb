# frozen_string_literal: true

module Bluepill
  # Warn, once each, about what bluepill 0.3.0 changes
  #
  # `bluepill load` loads a pill file before the daemon detaches, so a
  # warning goes to stderr, where the user sees it, and to bluepill's log at
  # warning, once there's a logger.
  #
  # @example
  #   Bluepill::Deprecation.warn(:evry, "bluepill 0.3.0 rejects the check option evry:. Remove it, or fix its name.")
  #   # DEPRECATION: bluepill 0.3.0 rejects the check option evry:. Remove it, or fix its name.
  #
  # @api private
  module Deprecation
    # The Ruby that bluepill 0.3.0 needs, or newer
    RUBY_REQUIRED = Gem::Version.new("3.0")

    @warned = {} #: Hash[untyped, bool]
    @logger = nil #: Logger?

    # Warn about a change, unless a warning of the same key was given
    #
    # @param [Object] key what the warning is about, such as
    #   [:check_option, :mem_usage, :evry]
    # @param [String] message what changes, in which version, and what to
    #   do now
    #
    # @return [void]
    #
    # @api private
    def self.warn(key, message)
      return if @warned.key?(key)

      @warned[key] = true
      line = "DEPRECATION: #{message}"
      $stderr.puts(line)
      @logger&.warning(line)
    end

    # Return the logger the warnings also go to
    #
    # @return [Logger, nil] the application's logger, or nil before there's
    #   one
    #
    # @api private
    def self.logger
      @logger
    end

    # Set the logger the warnings also go to
    #
    # @param [Logger, nil] logger the application's logger
    #
    # @return [void]
    #
    # @api private
    def self.logger=(logger)
      @logger = logger
    end

    # Forget the warnings given and the logger
    #
    # The specs call it before each example.
    #
    # @return [void]
    #
    # @api private
    def self.reset!
      @warned.clear
      @logger = nil
    end

    # Warn when bluepill runs on a Ruby that 0.3.0 doesn't support
    #
    # @param [String] version the Ruby's version
    #
    # @return [void]
    #
    # @api private
    def self.check_ruby(version = RUBY_VERSION)
      return unless Gem::Version.new(version) < RUBY_REQUIRED

      warn(:ruby, "bluepill 0.3.0 needs Ruby 3.0 or newer, or JRuby 9.4 or newer, and this is Ruby #{version}. " \
                  "Upgrade Ruby before you upgrade bluepill, or stay on 0.2.9.")
    end
  end
end

require "bluepill/deprecation/custom_checks"
