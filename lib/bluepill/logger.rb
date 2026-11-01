module Bluepill
  # Write bluepill's log, to syslog or a file, with prefixes
  #
  # A logger made with prefix_with writes through its parent, which adds
  # its own prefix, so a process's messages are tagged with its app's name
  # and its own, as in "[app:web] Going from up => down".
  #
  # @api private
  class Logger
    # The syslog priorities, each a method that logs a message
    #
    # @api private
    LOG_METHODS = [:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug].freeze

    # Make a logger
    #
    # @param [Hash{Symbol => Object}] options :logger, a parent logger to
    #   write through, :prefix, :stdout to echo messages there too,
    #   :log_file to write to instead of syslog, and :identity, the name
    #   syslog shows
    #
    # @return [void]
    #
    # @api private
    def initialize(options = {})
      @options  = options
      @logger   = options[:logger] || create_logger
      @prefix   = options[:prefix]
      @stdout   = options[:stdout]
      @prefixes = {}
    end

    # @!method emerg(msg, prefix = [])
    #   Log a message at the emergency priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
    # @!method alert(msg, prefix = [])
    #   Log a message at the alert priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
    # @!method crit(msg, prefix = [])
    #   Log a message at the critical priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
    # @!method err(msg, prefix = [])
    #   Log a message at the error priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
    # @!method warning(msg, prefix = [])
    #   Log a message at the warning priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
    # @!method notice(msg, prefix = [])
    #   Log a message at the notice priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
    # @!method info(msg, prefix = [])
    #   Log a message at the info priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
    # @!method debug(msg, prefix = [])
    #   Log a message at the debug priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>] prefix the prefixes of the loggers below
    #   @return [void]
    #   @api private
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

    # Return a logger that adds a prefix to this one's messages
    #
    # It's made once for each prefix, and kept.
    #
    # @param [String] prefix the prefix, such as a process's name
    #
    # @return [Logger] the prefixed logger
    #
    # @api private
    def prefix_with(prefix)
      @prefixes[prefix] ||= self.class.new(logger: self, prefix: prefix)
    end

    # Open the log file or syslog again, such as after log rotation
    #
    # @return [void]
    #
    # @api private
    def reopen
      logger = @logger
      if logger.instance_of?(self.class)
        logger.reopen
      else
        @logger = create_logger
      end
    end

  protected

    # Open the log file, or syslog if there isn't one
    #
    # @return [LoggerAdapter, Syslog] where the messages go
    #
    # @api private
    def create_logger
      if @options[:log_file]
        LoggerAdapter.new(@options.fetch(:log_file))
      else
        require_syslog
        Syslog.close if Syslog.opened? # need to explictly close it before reopening it
        Syslog.open(@options[:identity] || 'bluepilld', Syslog::LOG_PID, Syslog::LOG_LOCAL6)
      end
    end

    # Load syslog, which is only loaded when it's used
    #
    # Ruby 3.4 and newer don't include it by default, so apps that log to a
    # file don't need it in their Gemfile.
    #
    # @return [void]
    #
    # @raise [LoadError] with how to fix it, if syslog can't be loaded
    #
    # @api private
    def require_syslog
      require 'syslog'
    rescue LoadError
      message = 'Bluepill logs to syslog unless log_file is set, but the syslog library ' \
                "could not be loaded. Since Ruby 3.4 it's a separate gem, so add gem 'syslog' " \
                'to your Gemfile or set log_file.'
      raise LoadError, message
    end

    # A ::Logger that also answers to the syslog priorities' names
    #
    # @api private
    class LoggerAdapter < ::Logger
      # The ::Logger method for each syslog priority
      #
      # @api private
      LOGGER_EQUIVALENTS =
        {debug: :debug, err: :error, warning: :warn, info: :info, emerg: :fatal, alert: :warn, crit: :fatal, notice: :info}.freeze

      LOG_METHODS.each do |method|
        next if method == LOGGER_EQUIVALENTS[method]

        alias_method method, LOGGER_EQUIVALENTS[method]
      end
    end
  end
end
