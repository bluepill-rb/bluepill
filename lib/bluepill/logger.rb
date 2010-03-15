module Bluepill  
  class Logger
    LOG_METHODS = [:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug]
    
    def initialize(options = {})
      @options  = options
      @logger   = options[:logger] || self.create_logger
      @prefix   = options[:prefix]
      @stdout   = options[:stdout]
      @prefixes = {}
    end
    
    LOG_METHODS.each do |method|
      eval <<-END
        def #{method}(msg, prefix = [])
          if @logger.is_a?(self.class)
            @logger.#{method}(msg, [@prefix] + prefix)
          else
            s_prefix = prefix.size > 0 ? "[\#{prefix.compact.join(':')}] " : ""
            if @stdout
              $stdout.puts("[#{method}]: \#{s_prefix}\#{msg}")
              $stdout.flush
            end
            @logger.#{method}("\#{s_prefix}\#{msg}")
          end
        end
      END
    end
    
    def prefix_with(prefix)
      @prefixes[prefix] ||= self.class.new(:logger => self, :prefix => prefix)
    end
    
    def reopen
      if @logger.is_a?(self.class)
        @logger.reopen
      else
        @logger = create_logger
      end
    end
    
    protected
    def create_logger
      if @options[:log_file]
        LoggerAdapter.new(@options[:log_file])
      else
        Syslog.close if Syslog.opened? # need to explictly close it before reopening it
        Syslog.open(@options[:identity] || 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6)
      end
    end

    class LoggerAdapter < ::Logger
      LOGGER_EQUIVALENTS = 
        {:debug => :debug, :err => :error, :warning => :warn, :info => :info, :emerg => :fatal, :alert => :warn, :crit => :fatal, :notice => :info}
      
      LOG_METHODS.each do |method|
        next if method == LOGGER_EQUIVALENTS[method]
        alias_method method, LOGGER_EQUIVALENTS[method]
      end
    end 
  end
end
