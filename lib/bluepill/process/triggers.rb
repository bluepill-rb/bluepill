# frozen_string_literal: true

module Bluepill
  class Process
    # The triggers a Process tells of its transitions, such as Flapping
    #
    # @api private
    class Triggers
      include Enumerable

      # Return the logger the triggers write to
      #
      # @return [Logger, nil]
      #
      # @api private
      attr_reader :logger

      # Create an empty set of triggers
      #
      # @return [void]
      #
      # @api private
      def initialize = @triggers = []

      # Add a trigger of a class, for a process, with the triggers' logger
      #
      # @param [Class] klass the Trigger subclass, such as Triggers::Flapping
      # @param [Process] process the process it watches
      # @param [Hash{Symbol => Object}] options the trigger's options
      #
      # @return [Triggers] the triggers
      #
      # @api private
      def add(klass, process, **options) = self << klass.new(process, **options, logger: logger)

      # Add a trigger
      #
      # @param [Trigger] trigger the trigger
      #
      # @return [Triggers] the triggers
      #
      # @api private
      def <<(trigger)
        @triggers << trigger
        self
      end

      # Yield each trigger
      #
      # @yieldparam [Trigger] trigger a trigger
      #
      # @return [Array<Trigger>] the triggers
      #
      # @api private
      def each(&block) = @triggers.each(&block)

      # Set the logger, for the triggers and for any added later
      #
      # @param [Logger] logger the logger to use
      #
      # @return [void]
      #
      # @api private
      def logger=(logger)
        @logger = logger
        each { |trigger| trigger.logger = logger }
      end

      # Tell every trigger about a transition, before it happens
      #
      # A trigger can throw Trigger::HALT to stop the transition. An error a
      # trigger raises stops it too, and Process#tick logs it.
      #
      # @param [#from_name, #to_name, #loopback?] transition the transition
      #
      # @return [Array<Trigger>] the triggers
      #
      # @raise [StandardError] what a trigger raised
      #
      # @api private
      def notify(transition)
        # @triggers and not each, to save a call on every tick
        @triggers.each { |trigger| trigger.notify(transition) }
      end

      # Cancel the events every trigger scheduled
      #
      # The process does this when the user unmonitors it.
      #
      # @return [Array<Trigger>] the triggers
      #
      # @api private
      def reset! = each(&:reset!)
    end
  end
end
