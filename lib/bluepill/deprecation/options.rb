# frozen_string_literal: true

module Bluepill
  module Deprecation
    # The events that 0.3.0 takes for fires: and on_start_timeout
    EVENTS = %i[start stop unmonitor restart].freeze

    # The events, as a message lists them
    EVENTS_LIST = ":start, :stop, :unmonitor or :restart"

    # The options that a trigger takes for itself, besides its own
    TRIGGER_OPTIONS = %i[logger].freeze

    no_options = [] #: Array[Symbol]

    # The options of a check that takes none of its own, made once
    NO_OPTIONS = no_options.freeze

    # The options that each of bluepill's checks and triggers takes in 0.3.0
    CHECK_OPTIONS = {
      always_true: NO_OPTIONS,
      cpu_usage: %i[below],
      file_time: %i[filename below],
      flapping: %i[times within retry_in],
      http: %i[url kind pattern timeout open_timeout read_timeout verify_ssl],
      mem_usage: %i[below],
      running_time: %i[below],
      zombie_process: NO_OPTIONS
    }.freeze

    # The options that 0.3.0 needs, of the checks that need any
    #
    # An http check's url: isn't here, since 0.2 already fails without it.
    REQUIRED_OPTIONS = {
      cpu_usage: %i[below],
      file_time: %i[filename below],
      mem_usage: %i[below],
      running_time: %i[below]
    }.freeze

    # Warn about the options of a check that 0.3.0 rejects or needs
    #
    # Bluepill 0.3.0 fails the config for an option that a check doesn't
    # take, such as a misspelled one or within: on an http check, and for
    # one it needs and doesn't have, such as below: on a mem_usage check.
    # A custom check's options are its own business.
    #
    # @param [Symbol, String] name the check's name, such as :mem_usage
    # @param [Hash{Symbol => Object}] options the check's options
    # @param [Array<Symbol>] taken the options that bluepill takes for
    #   itself, ConditionWatch::WATCH_KEYS or TRIGGER_OPTIONS
    #
    # @return [void]
    #
    # @api private
    def self.check_options(name, options, taken)
      check = name.to_sym
      known = CHECK_OPTIONS[check]
      return unless known

      warn_unknown_options(check, options.keys - taken - known)
      warn_missing_options(check, REQUIRED_OPTIONS.fetch(check, NO_OPTIONS) - options.keys)
    end

    # Warn about the options of one of bluepill's checks that it doesn't take
    #
    # @param [Symbol] check the check's name
    # @param [Array<Object>] unknown the options
    #
    # @return [void]
    #
    # @api private
    def self.warn_unknown_options(check, unknown)
      unknown.each do |option|
        warn("bluepill 0.3.0 rejects the option #{option}: of checks #{check.inspect}, which 0.2 ignores. " \
             "Remove it, or fix its name.")
      end
    end

    # Warn about the options that one of bluepill's checks needs
    #
    # @param [Symbol] check the check's name
    # @param [Array<Symbol>] missing the options it doesn't have
    #
    # @return [void]
    #
    # @api private
    def self.warn_missing_options(check, missing)
      missing.each do |option|
        warn("bluepill 0.3.0 fails the config when checks #{check.inspect} has no #{option}: option, " \
             "which it needs to check anything in 0.2 too. Add it.")
      end
    end

    # Warn about a watch's options and events that 0.3.0 rejects
    #
    # @param [Symbol, String] name the check's name
    # @param [Hash{Symbol => Object}] options the watch's options
    # @param [Array<Object>] events the events it fires
    #
    # @return [void]
    #
    # @api private
    def self.check_watch(name, options, events)
      check_options(name, options, ConditionWatch::WATCH_KEYS)
      check_fires(name, events)
    end

    # Warn about events of a check's fires: that 0.3.0 rejects
    #
    # @param [Symbol, String] name the check's name
    # @param [Array<Object>] events the events it fires
    #
    # @return [void]
    #
    # @api private
    def self.check_fires(name, events)
      unknown = events - EVENTS
      return if unknown.empty?

      warn("bluepill 0.3.0 takes fires: only as #{EVENTS_LIST}, so fires: #{unknown.collect(&:inspect).join(", ")} " \
           "of checks #{name.to_sym.inspect} fails the config. Use the Symbols, such as fires: :stop.")
    end

    # Warn about a process's on_start_timeout that 0.3.0 rejects
    #
    # @param [String] process_name the process's name
    # @param [Hash{Symbol => Object}] attributes the process's attributes
    #
    # @return [void]
    #
    # @api private
    def self.check_on_start_timeout(process_name, attributes)
      return unless attributes.key?(:on_start_timeout)

      event = attributes.fetch(:on_start_timeout)
      return if EVENTS.include?(event)

      warn("bluepill 0.3.0 takes on_start_timeout only as #{EVENTS_LIST}, so process '#{process_name}''s " \
           "on_start_timeout of #{event.inspect} fails the config. Use the Symbols, such as on_start_timeout = :unmonitor.")
    end
  end
end
