module Bluepill
  class Logger
    LOG_METHODS = [:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug]
    
    def initialize(options = {})
      @logger = options[:logger] || Syslog.open(options[:identity] || 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6)
      @prefix = options[:prefix]
      @prefixes = {}
    end
    
    LOG_METHODS.each do |method|
      eval <<-END
        def #{method}(msg, prefix = [])
          if @logger.is_a?(self.class)
            @logger.#{method}(msg, [@prefix] + prefix)
          else
            prefix = prefix.size > 0 ? "[\#{prefix.compact.join(':')}] " : ""
            @logger.#{method}("\#{prefix}\#{msg}")
          end
        end
      END
    end
    
    def prefix_with(prefix)
      @prefixes[prefix] ||= self.class.new(:logger => self, :prefix => prefix)
    end
    
  end
end