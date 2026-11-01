module Bluepill
  HistoryValue = Struct.new(:value, :critical)

  class ConditionWatch
    attr_accessor :logger, :name

    # no need to recreate one every tick
    no_events = [] #: Array[Symbol]
    EMPTY_ARRAY = no_events.freeze

    def initialize(name, options = {})
      @name = name

      @logger = options.delete(:logger)
      @fires  = options.key?(:fires) ? Array(options.delete(:fires)) : [:restart]
      @every  = options.delete(:every)
      times   = options.delete(:times) || [1, 1]
      @times  = times.is_a?(Array) ? times : [times, times] # handles times: 5
      @include_children = options.delete(:include_children) || false

      clear_history!

      @process_condition = ProcessConditions[@name].new(options)
    end

    def run(pid, tick_number = Time.now.to_i)
      last_ran_at = @last_ran_at
      if last_ran_at.nil? || (last_ran_at + @every) <= tick_number
        @last_ran_at = tick_number

        begin
          value = @process_condition.run(pid, @include_children)
        rescue System::PsError => e
          # No data this time, so leave the history alone and check again next interval
          logger.warning("#{@name}: #{e.message}")
          return EMPTY_ARRAY
        rescue StandardError => e
          logger.err(e.backtrace)
          raise e
        end

        @history << HistoryValue.new(@process_condition.format_value(value), @process_condition.check(value))
        logger.info(to_s)

        return @fires if fired?
      end
      EMPTY_ARRAY
    end

    def clear_history!
      @history = Util::RotationalArray.new(@times.last)
    end

    def fired?
      @history.count { |v| !v.critical } >= @times.first
    end

    def to_s
      data = @history.collect { |v| "#{v.value}#{'*' unless v.critical}" }.join(', ')
      "#{@name}: [#{data}]\n"
    end
  end
end
