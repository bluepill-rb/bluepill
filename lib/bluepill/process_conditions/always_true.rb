# frozen_string_literal: true

module Bluepill
  module ProcessConditions
    # A check that always passes, for testing a config: `checks :always_true`
    #
    # @api private
    class AlwaysTrue < ProcessCondition
      # Return a value that's always fine
      #
      # @param [Integer, nil] _pid the process's pid
      # @param [Boolean] _include_children whether to include its children
      #
      # @return [Integer] always 1
      #
      # @api private
      def run(_pid, _include_children) = 1

      # Pass whatever the value is
      #
      # @param [Integer] _value what run read
      #
      # @return [Boolean] always true
      #
      # @api private
      def check?(_value) = true
    end
  end
end
