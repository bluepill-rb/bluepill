# frozen_string_literal: true

require "did_you_mean"

module Bluepill
  # The checks and triggers a config can name, by their underscored class
  # names
  #
  # Every subclass of ProcessConditions::ProcessCondition and of Trigger
  # adds itself when it's defined, in whatever module, so `checks
  # :log_size` finds a LogSize class anywhere. When two classes have the
  # same name, the one defined last wins.
  #
  # @api private
  module CheckRegistry
    # Each class, newest first, with the class it builds on and the methods
    # it must define
    @entries = [] #: Array[[Class, Class, Array[Symbol]]]

    # Add a check or trigger class
    #
    # @param [Class] klass the class
    # @param [Class] base ProcessConditions::ProcessCondition or Trigger
    # @param [Array<Symbol>] required the methods of the base that the class
    #   must define
    #
    # @return [void]
    #
    # @api private
    def self.add(klass, base, required) = @entries.unshift([klass, base, required])

    # Return the check or trigger class a config names
    #
    # @param [Symbol, String] name the underscored name, such as :mem_usage
    #
    # @return [Class] the ProcessConditions::ProcessCondition or Trigger
    #   subclass
    #
    # @raise [ConfigError] when no class has the name, or the class doesn't
    #   define the methods a check or trigger needs
    #
    # @api private
    def self.fetch(name)
      key = name.to_s
      entry = @entries.detect { |klass, _, _| check_name(klass).eql?(key) }
      raise ConfigError, unknown_message(key) unless entry

      klass, base, required = entry
      missing = missing_methods(klass, base, required)
      return klass if missing.empty?

      raise ConfigError, "#{klass}, the class of check '#{key}', must define #{missing.join(" and ")}"
    end

    # Return the names a config can use, for suggestions
    #
    # @return [Array<String>] the name of every class that defines the
    #   methods it needs
    #
    # @api private
    def self.names
      @entries.filter_map { |klass, base, required| check_name(klass) if missing_methods(klass, base, required).empty? }
    end

    # Return the name a config uses for a class
    #
    # @param [Class] klass the class
    #
    # @return [String, nil] its underscored name without its modules, such
    #   as "mem_usage", or nil for a class without a name
    #
    # @api private
    def self.check_name(klass)
      class_name = klass.name
      Util.underscore(class_name.rpartition("::").last) if class_name
    end

    # Return the methods a class must define and doesn't
    #
    # @param [Class] klass the class
    # @param [Class] base the class it builds on
    # @param [Array<Symbol>] required the methods it must define
    #
    # @return [Array<Symbol>] the methods it leaves to its base
    #
    # @api private
    def self.missing_methods(klass, base, required)
      required.select { |method| klass.instance_method(method).owner.equal?(base) }
    end

    # Return the message for a name no class has, with a suggestion
    #
    # @param [String] name the name
    #
    # @return [String]
    #
    # @api private
    def self.unknown_message(name)
      suggestion = DidYouMean::SpellChecker.new(dictionary: names).correct(name).first
      message = "Unknown check '#{name}'"
      suggestion ? "#{message}. Did you mean '#{suggestion}'?" : message
    end
  end
end
