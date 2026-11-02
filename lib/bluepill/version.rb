# frozen_string_literal: true

module Bluepill
  # The version of bluepill
  #
  # @example
  #   Bluepill::Version.to_s # => "0.2.3"
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
    def self.major
      0
    end

    # Return the minor version
    #
    # @example
    #   Bluepill::Version.minor # => 2
    #
    # @return [Integer] the minor version
    #
    # @api public
    def self.minor
      2
    end

    # Return the patch version
    #
    # @example
    #   Bluepill::Version.patch # => 3
    #
    # @return [Integer] the patch version
    #
    # @api public
    def self.patch
      3
    end

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
    #   Bluepill::Version.to_h # => {major: 0, minor: 2, patch: 3, pre: nil}
    #
    # @return [Hash{Symbol => Integer, nil}] the major, minor, patch and
    #   pre-release versions
    #
    # @api public
    def self.to_h
      {
        major: major,
        minor: minor,
        patch: patch,
        pre: pre
      }
    end

    # Return the version's parts, without a missing pre-release version
    #
    # @example
    #   Bluepill::Version.to_a # => [0, 2, 3]
    #
    # @return [Array<Integer>] the parts of the version
    #
    # @api public
    def self.to_a
      to_h.values.compact
    end

    # Return the version as a string
    #
    # @example
    #   Bluepill::Version.to_s # => "0.2.3"
    #
    # @return [String] the version, such as "0.2.3"
    #
    # @api public
    def self.to_s
      to_a.join(".")
    end
  end
end
