module BluePill
  class ConditionWatch
    def initialize(name, options = {})
      @name = name
      
      @fires = options.has_key?(:fires) ? [options.delete(:fires)].flatten : [:restart]
      @every = options.delete(:every)
      @times = options.delete(:times)
      
      @last_ran_at = nil
      @histroy = []
      
      @process_condition = ProcessConditions.name_to_class(@name).new(options)
    end
    
    def run(pid)
      if @last_ran_at.nil? || (@last_ran_at + @every) >= Time.now.to_i
        @last_ran_at = Time.now_to_i
        self.record_value(@process_condition.run(pid))
        return @fires if self.fired?
      end
      return []
    end
    
    def record_value(value)
      # TODO: record value in ProcessStatistics
      unless @times.nil?
        if @times.is_a?(Array)
          @history.push([value, @process_condition.check(value)])
          @history.shift if @history.size > @times[1]
        else
          @history = [value]
        end
      end
    end
    
    def clear_history!
      @history = []
      @last_ran_at = nil
    end
    
    def fired?
      @history.select {|v| !v[1] }.size >= @times[0]
    end
    
    def to_s
      @history.collect {|v| "#{v[0]}#{v[1] ? '' : '*'}"}.join(", ")
    end
  end
end