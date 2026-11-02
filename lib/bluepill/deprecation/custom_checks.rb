# frozen_string_literal: true

module Bluepill
  module Deprecation
    # The directory of bluepill's own code, which a custom check isn't in
    LIB_DIR = File.expand_path("../..", File.dirname(__FILE__))

    # The kinds of Method#parameters that take an argument by position
    POSITIONAL = %i[req opt].freeze

    # Warn about what a custom check's class does that 0.3.0 rejects
    #
    # Bluepill 0.3.0 passes a check's options as keyword arguments, calls
    # only check?, needs run and check?, and gives a MemUsage subclass bytes.
    #
    # @param [Class] klass the check's class
    #
    # @return [void]
    #
    # @api private
    def self.check_condition_class(klass)
      base = ProcessConditions::ProcessCondition
      warn_positional_options(klass, "check", 0)
      warn_check_methods(klass, base)
      return unless klass < ProcessConditions::MemUsage

      warn("bluepill 0.3.0 gives a check that subclasses MemUsage the memory usage in bytes, " \
           "where 0.2 gives kilobytes, so the run, check? and format_value of #{klass} " \
           "get values 1024 times larger. Change them when you upgrade.")
    end

    # Warn about what a custom trigger's class does that 0.3.0 rejects
    #
    # Bluepill 0.3.0 passes a trigger's options as keyword arguments, and
    # needs notify.
    #
    # @param [Class] klass the trigger's class
    #
    # @return [void]
    #
    # @api private
    def self.check_trigger_class(klass)
      warn_positional_options(klass, "trigger", 1)
      return unless klass.instance_method(:notify).owner.equal?(Trigger)

      warn("bluepill 0.3.0 fails the config when a trigger doesn't define notify, " \
           "and #{klass} doesn't. Define it, or remove the trigger.")
    end

    # Warn about a check or trigger whose initialize didn't keep its logger
    #
    # Bluepill 0.3.0 gives a check or trigger its logger only through the
    # logger: option, which the base class's initialize keeps, so one whose
    # initialize doesn't call super has none.
    #
    # @param [ProcessConditions::ProcessCondition, Trigger] check the check
    #   or trigger, just made
    # @param [Logger, nil] logger the logger it was given
    #
    # @return [void]
    #
    # @api private
    def self.check_logger(check, logger)
      return unless logger && check.logger.nil?

      warn("bluepill 0.3.0 gives #{check.class} its logger only through super, " \
           "which its initialize doesn't call, so it has no logger. Call super(**options) in its initialize.")
    end

    # Warn when code outside bluepill sets a check's or trigger's logger
    #
    # Bluepill 0.3.0 removes the logger= of ProcessCondition and Trigger.
    #
    # @param [ProcessConditions::ProcessCondition, Trigger] check the check
    #   or trigger whose logger is set
    # @param [Thread::Backtrace::Location, nil] location where logger= was
    #   called from
    #
    # @return [void]
    #
    # @api private
    def self.check_logger_writer(check, location)
      path = location&.path
      return if path.nil? || File.expand_path(path).start_with?(LIB_DIR)

      warn("bluepill 0.3.0 removes the logger= of checks and triggers, which #{location} " \
           "calls on #{check.class}. Let it get its logger from super(**options) in its initialize.")
    end

    # Warn about a trigger that dispatches an event that isn't a Symbol
    #
    # Bluepill 0.3.0 takes only the Symbols of a process's events.
    #
    # @param [Trigger] trigger the trigger
    # @param [Object] event the event it dispatches
    #
    # @return [void]
    #
    # @api private
    def self.check_trigger_event(trigger, event)
      return if event.instance_of?(Symbol)

      warn("bluepill 0.3.0 takes a process's events only as Symbols, so #{trigger.class} " \
           "fails when it dispatches #{event.inspect}. Dispatch #{event.to_s.to_sym.inspect}, which 0.2.9 takes too.")
    end

    # Warn about a custom initialize that takes its options by position
    #
    # @param [Class] klass the check's or trigger's class
    # @param [String] kind "check" or "trigger"
    # @param [Integer] positional how many arguments 0.3.0 passes by
    #   position, 1 for a trigger's process
    #
    # @return [void]
    #
    # @api private
    def self.warn_positional_options(klass, kind, positional)
      initialize = klass.instance_method(:initialize)
      return unless custom?(initialize) && positional_options?(initialize, positional)

      warn("bluepill 0.3.0 passes a #{kind}'s options as keyword arguments, " \
           "so the initialize of #{klass}, which takes them as a Hash, fails when it calls super. " \
           "Name the options it needs, as in def initialize(path:, below:, **options), " \
           "and call super(**options), which 0.2.9 takes too.")
    end

    # Warn about a custom check that defines check, or not run and check?
    #
    # @param [Class] klass the check's class
    # @param [Class] base ProcessConditions::ProcessCondition
    #
    # @return [void]
    #
    # @api private
    def self.warn_check_methods(klass, base)
      defines_check = !klass.instance_method(:check).owner.equal?(base)
      defines_predicate = !klass.instance_method(:check?).owner.equal?(base)
      if defines_check && !defines_predicate
        warn("bluepill 0.3.0 calls only check?, so #{klass}, which defines check, fails the config. " \
             "Rename its check method check?, which 0.2.9 calls too.")
      end
      warn_missing_methods(klass, base, defines_check || defines_predicate)
    end

    # Warn about a custom check that doesn't define run, or check? or check
    #
    # @param [Class] klass the check's class
    # @param [Class] base ProcessConditions::ProcessCondition
    # @param [Boolean] checks whether it defines check? or check
    #
    # @return [void]
    #
    # @api private
    def self.warn_missing_methods(klass, base, checks)
      missing = [] #: Array[String]
      missing << "run" if klass.instance_method(:run).owner.equal?(base)
      missing << "check?" unless checks
      return if missing.empty?

      warn("bluepill 0.3.0 fails the config when a check doesn't define run and check?, " \
           "and #{klass} doesn't define #{missing.join(" or ")}. Define it, or remove the check.")
    end

    # Return whether a method is defined outside bluepill's own code
    #
    # @param [UnboundMethod] method the method
    #
    # @return [Boolean] true for a method of a pill file or a library
    #
    # @api private
    def self.custom?(method)
      file, = method.source_location
      !file.nil? && !File.expand_path(file).start_with?(LIB_DIR)
    end

    # Return whether an initialize takes options by position
    #
    # It does if it takes more arguments by position than 0.3.0 passes.
    #
    # @param [UnboundMethod] initialize the initialize method
    # @param [Integer] positional how many arguments 0.3.0 passes by
    #   position
    #
    # @return [Boolean]
    #
    # @api private
    def self.positional_options?(initialize, positional)
      parameters = initialize.parameters
      parameters.any? { |type, _| type.equal?(:rest) } ||
        parameters.count { |type, _| POSITIONAL.include?(type) } > positional
    end
  end
end
