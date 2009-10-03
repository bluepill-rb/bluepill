module Bluepill
  class Logger
    def initialize(logger = nil, prefix = nil)
      @logger = logger || Syslog.open('bluepill', Syslog::LOG_PID | Syslog::LOG_CONS, Syslog::LOG_LOCAL6)
      @prefix = prefix
    end
    
    [:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug].each do |method|
      eval <<-END
        def #{method}(*args)
          with_prefix = args.collect {|s| "\#{@prefix}\#{s}" } if \@prefix
          @logger.#{method}(with_prefix)
        end
      END
    end
  end
end