# frozen_string_literal: true

module Bluepill
  class Process
    # A process's move from one state to another, as triggers and the
    # transition callbacks see it
    #
    # @api private
    class Transition
      # Return the state the process is leaving
      #
      # @return [Symbol]
      #
      # @api private
      attr_reader :from_name

      # Return the state the process is going to
      #
      # @return [Symbol]
      #
      # @api private
      attr_reader :to_name

      # Create a transition between two states
      #
      # @param [Symbol] from_name the state the process is leaving
      # @param [Symbol] to_name the state the process is going to
      #
      # @return [void]
      #
      # @api private
      def initialize(from_name, to_name)
        @from_name = from_name
        @to_name = to_name
      end

      # Return whether the process stays in the same state
      #
      # @return [Boolean]
      #
      # @api private
      def loopback? = from_name.equal?(to_name)
    end
  end
end
