module Bluepill
  # Small helpers bluepill keeps for itself
  #
  # @api private
  module Util
    # Turn a snake_case name into CamelCase, as ActiveSupport's camelize does
    #
    # @example
    #   Bluepill::Util.camelize(:mem_usage) # => "MemUsage"
    #
    # @param [#to_s] name a name such as :mem_usage
    #
    # @return [String] the name in CamelCase, such as "MemUsage"
    #
    # @api private
    def self.camelize(name)
      name.to_s.sub(/\A[a-z]/, &:upcase).gsub(/_[a-z\d]*/i) { |part| part.delete('_').capitalize }
    end

    # Turn a CamelCase name into snake_case, as ActiveSupport's underscore does
    #
    # @example
    #   Bluepill::Util.underscore("HTTPCheck") # => "http_check"
    #
    # @param [String] name a name such as "Flapping"
    #
    # @return [String] the name in snake_case, such as "flapping"
    #
    # @api private
    def self.underscore(name)
      name.gsub(/([A-Z\d])([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
