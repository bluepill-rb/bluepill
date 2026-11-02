module Bluepill
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

  # Runs a process's check every so often, and fires its events when the
  # check fails often enough
  #
  # A config's `checks :mem_usage, every: 10.seconds, below: 100.megabytes,
  # times: [3, 5]` makes one: it runs every 10 seconds, and fires (restarts
  # the process, by default) when 3 of the last 5 values failed.
  #
  # @api private
  class ConditionWatch
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

      @logger = options.delete(:logger)
      @fires  = options.key?(:fires) ? Array(options.delete(:fires)) : [:restart]
      @every  = options.delete(:every)
      @times  = Array(options.delete(:times) || 1) # handles times: 5
      @include_children = options.delete(:include_children) || false

      clear_history!

      # The condition gets the logger while it's created, so its own
      # initialize can log, and again after, in case that initialize doesn't
      # call super
      @process_condition = ProcessConditions[@name].new(options.merge(logger: @logger))
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
    # @param [Integer] tick_number the current time, in seconds
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
    # @param [Integer] tick_number the current time, in seconds
    #
    # @return [Array<Symbol>] the events to fire, empty unless the check
    #   ran and failed often enough
    #
    # @raise [StandardError] whatever the check raised, other than a
    #   System::PsError, after logging it
    #
    # @api private
    def run(pid, tick_number = Integer(Time.now))
      # The same test as due?, written out to save a call on every check
      last_ran_at = @last_ran_at
      if last_ran_at.nil? || (last_ran_at + @every) <= tick_number
        @last_ran_at = tick_number

        begin
          value = @process_condition.run(pid, @include_children)
        rescue System::PsError => e
          # No data this time, so leave the history alone and check again next interval
          logger.warning("#{@name}: #{e}")
          return EMPTY_ARRAY
        rescue StandardError => e
          logger.err(e.backtrace)
          raise
        end

        @history << HistoryValue.new(@process_condition.format_value(value), @process_condition.check?(value))
        logger.info(to_s)

        return @fires if fired?
      end
      EMPTY_ARRAY
    end

    # Forget the values the check read, as when the process changes state
    #
    # @return [Util::RotationalArray<HistoryValue>] the new, empty history
    #
    # @api private
    def clear_history!
      @history = Util::RotationalArray.new(@times.last)
    end

    # Return whether enough of the last values failed for the watch to fire
    #
    # @return [Boolean] true when the failures reach the times the check
    #   allows
    #
    # @api private
    def fired?
      @history.count { |v| !v.critical } >= @times.first
    end

    # Return the check's name and history, as the log shows it
    #
    # @return [String] such as "mem_usage: [312MB, 401MB*]", where * marks a
    #   value that failed
    #
    # @api private
    def to_s
      data = @history.collect { |v| "#{v.value}#{'*' unless v.critical}" }.join(', ')
      "#{@name}: [#{data}]\n"
    end
  end
end
