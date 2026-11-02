# frozen_string_literal: true

module Bluepill
  # The version of bluepill
  #
  # @example
  #   Bluepill::Version.to_s # => "0.3.2"
  #
  # @api public
  module Version
    # Return the major version
    #
    # @example
    #   Bluepill::Version.major # => 0
    #
    # @return [Integer] the major version
    #
    # @api public
    def self.major = 0

    # Return the minor version
    #
    # @example
    #   Bluepill::Version.minor # => 3
    #
    # @return [Integer] the minor version
    #
    # @api public
    def self.minor = 3

    # Return the patch version
    #
    # @example
    #   Bluepill::Version.patch # => 2
    #
    # @return [Integer] the patch version
    #
    # @api public
    def self.patch = 2

    # Return the pre-release version
    #
    # @example
    #   Bluepill::Version.pre # => nil
    #
    # @return [Integer, nil] the pre-release version, or nil for a release
    #
    # @api public
    def self.pre
    end

    # Return the version's parts by name
    #
    # @example
    #   Bluepill::Version.to_h # => {major: 0, minor: 3, patch: 2, pre: nil}
    #
    # @return [Hash{Symbol => Integer, nil}] the major, minor, patch and
    #   pre-release versions
    #
    # @api public
    def self.to_h
      {
        major:,
        minor:,
        patch:,
        pre:
      }
    end

    # Return the version's parts, without a missing pre-release version
    #
    # @example
    #   Bluepill::Version.to_a # => [0, 3, 2]
    #
    # @return [Array<Integer>] the parts of the version
    #
    # @api public
    def self.to_a = to_h.values.compact

    # Return the version as a string
    #
    # @example
    #   Bluepill::Version.to_s # => "0.3.2"
    #
    # @return [String] the version, such as "0.3.2"
    #
    # @api public
    def self.to_s = to_a.join(".")
  end
end
