module Bluepill
  # Small helpers for the rest of bluepill
  #
  # @api private
  module Util
    # An array that drops its oldest element when it grows past its capacity
    #
    # Watches keep their last few values in one, and processes their last
    # few events.
    #
    # @api private
    class RotationalArray < Array
      # Create an empty array that holds at most size elements
      #
      # @param [Integer] size the most elements it holds
      #
      # @return [void]
      #
      # @api private
      def initialize(size)
        @capacity = size

        super() # no size - intentionally
      end

      # Add an element, dropping the oldest one when it's full
      #
      # @param [Object] value the element to add
      #
      # @return [RotationalArray] self
      #
      # @api private
      def push(value)
        super

        shift if length > @capacity
        self
      end
      alias_method :<<, :push
    end
  end
end
