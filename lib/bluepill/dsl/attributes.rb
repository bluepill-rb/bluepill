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
    # each. A reader returns nil for an attribute that isn't set. A block
    # that {#evaluate} runs fails with a {ConfigError} that names the
    # closest attribute for any other call on the proxy, so a misspelled
    # attribute fails when the pill file loads instead of being ignored.
    # The class sets @attributes to a Hash, and defines attribute_owner,
    # which names it in the error.
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

      # Run a block of the pill file with self set to the proxy
      #
      # instance_eval also passes the proxy to a block that takes an
      # argument. A call of a method the proxy doesn't have, such as a
      # misspelled attribute, fails with a ConfigError instead, with the
      # backtrace of the call, so it still points at the pill file's line.
      # Any other NameError, such as one raised on another object, passes
      # through as it is.
      #
      # @yield runs with self set to the proxy
      # @yieldparam [Attributes] proxy the proxy
      # @yieldreturn [void]
      #
      # @return [Object] what the block returns
      #
      # @raise [ConfigError] for a method the proxy doesn't have
      #
      # @api private
      def evaluate(&block)
        instance_eval(&block)
      rescue NameError => e
        raise unless e.receiver.equal?(self)

        raise ConfigError, unknown_attribute_message(e.name), e.backtrace
      end

      private

      # Return the message for a call of an attribute that isn't there
      #
      # It names the attribute and what it was called on, and the closest
      # attribute there is, when one is close enough.
      #
      # @param [Symbol] name the method's name
      #
      # @return [String] the message
      #
      # @api private
      def unknown_attribute_message(name)
        attribute = name.to_s.delete_suffix("=")
        message = "Unknown attribute '#{attribute}' for #{attribute_owner}"
        suggestion = suggest(attribute)
        suggestion ? "#{message}. Did you mean '#{suggestion}'?" : message
      end

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
