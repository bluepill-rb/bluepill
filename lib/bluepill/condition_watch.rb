module Bluepill
  class ConditionWatch
    attr_accessor :logger, :name
    EMPTY_ARRAY = [].freeze # no need to recreate one every tick
    
    def initialize(name, options = {})
      @name = name

      @logger = options.delete(:logger)      
      @fires = options.has_key?(:fires) ? Array(options.delete(:fires)) : [:restart]
      @every = options.delete(:every)
      @times = options.delete(:times) || [1,1]
      @times = [@times, @times] unless @times.is_a?(Array) # handles :times => 5

      self.clear_history!
      
      @process_condition = ProcessConditions[@name].new(options)
    end
    
    def run(pid, tick_number = Time.now.to_i)
      if @last_ran_at.nil? || (@last_ran_at + @every) <= tick_number
        @last_ran_at = tick_number
        self.record_value(@process_condition.run(pid))
        return @fires if self.fired?
      end
      EMPTY_ARRAY
    end
    
    def record_value(value)
      # TODO: record value in ProcessStatistics
      @history[@history_index] = [value, @process_condition.check(value)]
      @history_index = (@history_index + 1) % @history.size
      self.logger.info(self.to_s)
    end
    
    def clear_history!
      @last_ran_at = nil
      @history = Array.new(@times[1])
      @history_index = 0
    end
    
    def fired?
      @history.select {|v| v && !v[1]}.size >= @times[0]
    end
    
    def to_s
      # TODO: this will be out of order because of the way history values are assigned
      # use (@history[(@history_index - 1)..1] + @history[0..(@history_index - 1)]).
      #       collect {|v| "#{v[0]}#{v[1] ? '' : '*'}"}.join(", ")
      # but that's gross so... it's gonna be out of order till we figure out a better way to get it in order
      data = @history.collect {|v| "#{@process_condition.format_value(v[0])}#{v[1] ? '' : '*'}" if v}.compact.join(", ")
      "#{@name}: [#{data}]"
    end
  end
end