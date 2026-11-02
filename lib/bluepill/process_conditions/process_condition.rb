# frozen_string_literal: true

module Bluepill
  module ProcessConditions
    # Checks something about a process, as one of a process's checks
    #
    # A ConditionWatch runs the condition every so often. The condition reads
    # a value (run), says whether the value is fine (check), and formats it
    # for the watch's history (format_value). Subclasses implement run and
    # check?, and add themselves to CheckRegistry by their underscored
    # name, in whatever module they're defined.
    #
    # @api private
    class ProcessCondition
      # The methods a subclass must define
      #
      # @api private
      REQUIRED_METHODS = %i[run check?].freeze

      # Add a subclass to the checks a config can name
      #
      # A config names it by its underscored name, such as :mem_usage.
      #
      # @param [Class] klass the subclass
      #
      # @return [void]
      #
      # @api private
      def self.inherited(klass)
        super
        CheckRegistry.add(klass, ProcessCondition, REQUIRED_METHODS)
      end

      # Return the logger the condition can write to
      #
      # It's the watch's logger, so lines carry the app's and the process's
      # names. A condition that calls super in its own initialize has it from
      # then on.
      #
      # @example
      #   logger.info("free disk: #{free}")
      #
      # @return [Logger, nil] the process's logger
      #
      # @api public
      attr_accessor :logger

      # Create a condition with the options a config gave its check
      #
      # @param [Logger, nil] logger the watch's logger
      #
      # @return [void]
      #
      # @raise [ArgumentError] for an option that no condition takes
      #
      # @api private
      def initialize(logger: nil)
        @logger = logger
      end

      # Read the value to check from the process
      #
      # @param [Integer, nil] _pid the process's pid
      # @param [Boolean] _include_children whether to include its children
      #
      # @return [Object] the value to check
      #
      # @raise [RuntimeError] unless a subclass implements it
      #
      # @api private
      def run(_pid, _include_children) = raise("Implement in subclass!")

      # Return whether a value is fine
      #
      # @param [Object] _value what run read
      #
      # @return [Boolean] true when the value is fine, false when it's not
      #
      # @raise [RuntimeError] unless a subclass implements it
      #
      # @api private
      def check?(_value) = raise("Implement in subclass!")

      # Format a value for the watch's history and log
      #
      # @param [Object] value what run read
      #
      # @return [Object] the value as the history shows it, by default the
      #   value itself
      #
      # @api private
      def format_value(value) = value
    end
  end
end
