module Bluepill
  module Version
    # @return [Integer]
    def self.major
      0
    end

    # @return [Integer]
    def self.minor
      1
    end

    # @return [Integer]
    def self.patch
      4
    end

    # @return [Integer, NilClass]
    def self.pre; end

    # @return [Hash]
    def self.to_h
      {
        major: major,
        minor: minor,
        patch: patch,
        pre: pre,
      }
    end

    # @return [Array]
    def self.to_a
      to_h.values.compact
    end

    # @return [String]
    def self.to_s
      to_a.join('.')
    end
  end
end
