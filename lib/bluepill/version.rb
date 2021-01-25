module Bluepill
  module Version
  module_function

    # @return [Integer]
    def major
      0
    end

    # @return [Integer]
    def minor
      1
    end

    # @return [Integer]
    def patch
      4
    end

    # @return [Integer, NilClass]
    def pre
      nil
    end

    # @return [Hash]
    def to_h
      {
        major: major,
        minor: minor,
        patch: patch,
        pre: pre,
      }
    end

    # @return [Array]
    def to_a
      to_h.values.compact
    end

    # @return [String]
    def to_s
      to_a.join('.')
    end
  end
end
