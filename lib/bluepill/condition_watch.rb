# frozen_string_literal: true

require "bluepill/util/log_error"

module Bluepill
  # Runs a process's check every so often, and fires its events when the
  # check fails often enough
  #
  # A config's `checks :mem_usage, every: 10.seconds, below: 100.megabytes,
  # times: [3, 5]` makes one: it runs every 10 seconds, and fires (restarts
  # the process, by default) when 3 of the last 5 values failed.
  #
  # @api private
  class ConditionWatch
    # One entry of a watch's history: the value it read, as its log shows it,
    # and whether the value was fine
    #
    # @!attribute value
    #   Return the value as the history shows it
    #
    #   @return [#to_s] the formatted value
    #
    #   @api private
    #
    # @!attribute critical
    #   Return whether the value was fine
    #
    #   It's true for a value that passed the check, and false for one that
    #   counts toward the watch firing.
    #
    #   @return [Boolean] whether the value passed the check
    #
    #   @api private
    #
    # @api private
    HistoryValue = Struct.new(:value, :critical)

    # Return the logger the watch writes its history to
    #
    # @return [Logger] the process's logger
    #
    # @api private
    attr_reader :logger

    # Return the check's name, such as :mem_usage
    #
    # @return [Symbol] the name a config gave the check
    #
    # @api private
    attr_accessor :name

    no_events = [] #: Array[Symbol]

    # The events of a run that fires nothing, made once instead of every tick
    #
    # @api private
    EMPTY_ARRAY = no_events.freeze

    # The options the watch takes for itself, which the check doesn't get
    #
    # @api private
    WATCH_KEYS = %i[logger fires every times include_children].freeze

    # Create a watch of a check
    #
    # @param [Symbol] name the check's name, such as :mem_usage
    # @param [Hash{Symbol => Object}] options the check's options. The
    #   watch takes :logger, :fires (the events to fire, [:restart] by
    #   default), :every (seconds between runs), :times (how many of the
    #   last values must fail, as a count or [count, of]), and
    #   :include_children. The check gets the rest.
    #
    # @return [void]
    #
    # @api private
    def initialize(name, options = {})
      @name = name
      @logger = options[:logger]
      @fires = Array(options.fetch(:fires, :restart))
      @every = options[:every]
      # times: 5 means 5 of the last 5, and times: [3, 5] 3 of the last 5
      times = Array(options[:times] || 1) #: Array[Integer]
      @required = times.first #: Integer
      @window = times.last #: Integer
      @include_children = options[:include_children] || false
      clear_history!
      create_condition(options)
    end

    # Create the check, with the options the watch doesn't take for itself
    #
    # The condition gets the logger while it's created, so its own
    # initialize can log, and again after, in case that initialize doesn't
    # call super.
    #
    # @param [Hash{Symbol => Object}] options the options the watch was
    #   created with, which stay as they are
    #
    # @return [void]
    #
    # @api private
    def create_condition(options)
      condition_options = options.reject { |key, _| WATCH_KEYS.include?(key) }
      condition_options[:logger] = @logger
      @process_condition = ProcessConditions[@name].new(condition_options)
      self.logger = @logger
    end

    # Set the logger the watch and its condition write to
    #
    # The process sets its watches' logger again when it gets a logger of
    # its own, such as one with its group's name.
    #
    # @param [Logger] logger the process's logger
    #
    # @return [void]
    #
    # @api private
    def logger=(logger)
      @logger = logger
      @process_condition.logger = logger
    end

    # Return whether the check is due
    #
    # It's due on its first run, and then every `every` seconds.
    #
    # @param [Integer] tick_number the time, from Clock.now
    #
    # @return [Boolean]
    #
    # @api private
    def due?(tick_number)
      last_ran_at = @last_ran_at
      last_ran_at.nil? || (last_ran_at + @every) <= tick_number
    end

    # Run the check if it's due, and return the events to fire
    #
    # A check is due on its first run, and then every `every` seconds. A
    # run adds the value to the history and logs the history.
    #
    # @param [Integer, nil] pid the process's pid
    # @param [Integer] tick_number the time, from Clock.now
    #
    # @return [Array<Symbol>] the events to fire, empty unless the check
    #   ran and failed often enough
    #
    # @api private
    def run(pid, tick_number = Clock.now)
      # The same test as due?, written out to save a call on every check.
      # An if, not a guard clause: the guard ran 3% slower on the zombie
      # benchmark, with the same instructions.
      last_ran_at = @last_ran_at
      if last_ran_at.nil? || (last_ran_at + @every) <= tick_number
        @last_ran_at = tick_number
        return run_check(pid)
      end
      EMPTY_ARRAY
    end

    # Run the check, add its value to the history, and log the history
    #
    # A check that raises is skipped: it adds nothing to the history and
    # fires nothing, and runs again at its next interval.
    #
    # @param [Integer, nil] pid the process's pid
    #
    # @return [Array<Symbol>] the events to fire, empty unless enough of
    #   the last values failed for the watch to fire
    #
    # @api private
    def run_check(pid)
      value = @process_condition.run(pid, @include_children)
      @history << HistoryValue.new(@process_condition.format_value(value), @process_condition.check?(value))
      logger.info(to_s)
      # Fire when enough of the values in the window failed
      return @fires if @history.count { |v| !v.critical } >= @required

      EMPTY_ARRAY
    rescue => e
      check_failed(e)
    end

    # Log an error the check raised
    #
    # A failed ps is a warning, since it says nothing about the check. Any
    # other error is logged with its backtrace. Either way, the check reads
    # nothing this time.
    #
    # @param [StandardError] error what the check raised
    #
    # @return [Array<Symbol>] no events
    #
    # @api private
    def check_failed(error)
      if error.is_a?(System::PsError)
        logger.warning("#{@name}: #{error}")
      else
        Util.log_error(logger, "#{@name} check failed", error)
      end
      EMPTY_ARRAY
    end

    # Forget the values the check read, as when the process changes state
    #
    # @return [Util::RotationalArray<HistoryValue>] the new, empty history
    #
    # @api private
    def clear_history!
      @history = Util::RotationalArray.new(@window)
    end

    # Return the check's name and history, as the log shows it
    #
    # @return [String] such as "mem_usage: [312MB, 401MB*]", where * marks a
    #   value that failed
    #
    # @api private
    def to_s
      data = @history.collect { |v| "#{v.value}#{"*" unless v.critical}" }.join(", ")
      "#{@name}: [#{data}]\n"
    end
  end
end
