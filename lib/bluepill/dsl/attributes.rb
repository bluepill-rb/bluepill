# frozen_string_literal: true

require "did_you_mean"

module Bluepill
  # The parts that the pill file's application and process blocks share
  #
  # @api private
  module DSL
    # The attributes that a pill file sets with `name = value`
    #
    # A class that includes it names its attributes with
    # {ClassMethods#attribute}, which defines a writer and a reader for
    # each. A reader returns nil for an attribute that isn't set. Any other
    # call fails with a {ConfigError} that names the closest attribute, so
    # a misspelled one fails when the pill file loads instead of being
    # ignored. The class sets @attributes to a Hash, and defines
    # attribute_owner, which names it in the error.
    #
    # @api private
    module Attributes
      # Give a class that includes the module its attribute macro
      #
      # @param [Class] base the class
      #
      # @return [void]
      #
      # @api private
      def self.included(base)
        base.extend(ClassMethods)
      end

      # The attribute macro of a class that includes {Attributes}
      #
      # @api private
      module ClassMethods
        # Return the attributes that a pill file can set
        #
        # @return [Array<Symbol>] the attributes' names
        #
        # @api private
        attr_reader :attribute_names

        # Define a writer and a reader for each attribute
        #
        # @param [Array<Symbol>] names the attributes' names
        #
        # @return [void]
        #
        # @api private
        def attribute(*names)
          @attribute_names = names.freeze
          names.each do |name|
            define_method(name) do
              # @type self: Attributes
              attributes[name]
            end
            define_method(:"#{name}=") do |value|
              # @type self: Attributes
              attributes[name] = value
            end
          end
        end
      end

      # Return the attributes that the pill file set, by name
      #
      # @return [Hash{Symbol => Object}] the attributes
      #
      # @api private
      attr_reader :attributes

      private

      # Fail on a call of an attribute that isn't there
      #
      # The message names the attribute and what it was called on, and the
      # closest attribute there is, when one is close enough.
      #
      # @param [Symbol] name the method's name
      #
      # @return [void] it never returns
      #
      # @raise [ConfigError] always
      #
      # @api private
      def method_missing(name, *)
        attribute = name.to_s.delete_suffix("=")
        message = "Unknown attribute '#{attribute}' for #{attribute_owner}"
        suggestion = suggest(attribute)
        message += ". Did you mean '#{suggestion}'?" if suggestion
        raise ConfigError, message
      end

      # Return false, since method_missing defines no method, and only fails
      #
      # Standard asks for it beside method_missing. Object's own returns
      # false too, so mutant can't tell its `super` mutation apart, and it's
      # marked mutant:disable for that.
      #
      # @param [Symbol] _name the method's name
      # @param [Boolean] _include_private ignored
      #
      # @return [false]
      #
      # @api private
      def respond_to_missing?(_name, _include_private) = false

      # Return the attribute that's closest to a misspelled one
      #
      # Ruby's did_you_mean picks it, as it picks a method for a misspelled
      # one.
      #
      # @param [String] attribute the misspelled attribute
      #
      # @return [String, nil] the closest attribute, or nil
      #
      # @api private
      def suggest(attribute)
        names = self.class.attribute_names.collect(&:to_s)
        DidYouMean::SpellChecker.new(dictionary: names).correct(attribute).first
      end
    end
  end
end
