module Bluepill
  class Logger
    LOG_METHODS = [:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug].freeze

    def initialize(options = {})
      @options  = options
      @logger   = options[:logger] || create_logger
      @prefix   = options[:prefix]
      @stdout   = options[:stdout]
      @prefixes = {}
    end

    LOG_METHODS.each do |method|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
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
      RUBY
    end

    def prefix_with(prefix)
      @prefixes[prefix] ||= self.class.new(logger: self, prefix: prefix)
    end

    def reopen
      logger = @logger
      if logger.instance_of?(self.class)
        logger.reopen
      else
        @logger = create_logger
      end
    end

  protected

    def create_logger
      if @options[:log_file]
        LoggerAdapter.new(@options.fetch(:log_file))
      else
        require_syslog
        Syslog.close if Syslog.opened? # need to explictly close it before reopening it
        Syslog.open(@options[:identity] || 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6)
      end
    end

    # Syslog is only loaded when it's used. Ruby 3.4 and newer don't include
    # it by default, so apps that log to a file don't need it in their Gemfile.
    def require_syslog
      require 'syslog'
    rescue LoadError
      message = 'Bluepill logs to syslog unless log_file is set, but the syslog library ' \
                "could not be loaded. Since Ruby 3.4 it's a separate gem, so add gem 'syslog' " \
                'to your Gemfile or set log_file.'
      raise LoadError, message
    end

    class LoggerAdapter < ::Logger
      LOGGER_EQUIVALENTS =
        {debug: :debug, err: :error, warning: :warn, info: :info, emerg: :fatal, alert: :warn, crit: :fatal, notice: :info}.freeze

      LOG_METHODS.each do |method|
        next if method == LOGGER_EQUIVALENTS[method]

        alias_method method, LOGGER_EQUIVALENTS[method]
      end
    end
  end
end
