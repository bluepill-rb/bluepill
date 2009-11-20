module Bluepill  
  class Logger
    LOG_METHODS = [:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug]
    
    def initialize(options = {})
      @logger = options[:logger] || self.create_logger(options)
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
    
    protected
    def create_logger(options)
      if options[:log_file]
        LoggerAdapter.new(options)
      else
        SyslogAdapter.new(options)
      end
    end
    
    class SyslogAdapter
      def initialize(options)
        @logger = Syslog.open(options[:identity] || 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6)
      end
      
      LOG_METHODS.each do |method|
        class_eval <<-END
          def #{method}(msg)
            @logger.#{method}(msg)
          end
        END
      end
    end

    class LoggerAdapter
      LOGGER_EQUIVALENTS = 
        {:debug => :debug, :err => :error, :warning => :warn, :info => :info, :emerg => :fatal, :alert => :warn, :crit => :fatal, :notice => :info}

      def initialize(options)
        @logger = ::Logger.new(options[:log_file])
      end
      
      LOG_METHODS.each do |method|
        class_eval <<-END
          def #{method}(msg)
            @logger.#{LOGGER_EQUIVALENTS[method]}(msg)
          end
        END
      end
      
    end 
  end
end