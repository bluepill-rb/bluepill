module Bluepill
  # Write bluepill's log, to syslog or a file, with prefixes
  #
  # A logger made with prefix_with adds its prefix to its parent's, so a
  # process's messages are tagged with its app's name and its own, as in
  # "[app:web] Going from up => down". Every logger made from the same one
  # writes to the same place, which reopen can change for all of them.
  #
  # @api private
  class Logger
    # The syslog priorities, most severe first, each a method that logs a
    # message
    #
    # @api private
    LOG_METHODS = [:emerg, :alert, :crit, :err, :warning, :notice, :info, :debug].freeze

    # Make a logger
    #
    # @param [Hash{Symbol => Object}] options :logger, a parent logger to
    #   write through, or an object to write to, :prefix, :stdout to echo
    #   messages there too, :log_file to write to instead of syslog,
    #   :identity, the name syslog shows, and :log_level, the least severe
    #   priority to log (debug, so everything, by default)
    #
    # @return [void]
    #
    # @raise [ArgumentError] if :log_level isn't one of {LOG_METHODS}
    #
    # @api private
    def initialize(options = {})
      @options = options
      @logger = options[:logger] || create_logger
      @prefix = options[:prefix]
      @prefixes = {}
      # Set here, and not in settings_from, since Ruby makes room in a new
      # Logger for the instance variables that initialize sets
      @level, @names, @stdout, @sink = settings_from(@logger, priority(options[:log_level] || :debug))
      @label = label(@names)
    end

    # @!method emerg(msg, prefix = nil)
    #   Log a message at the emergency priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    # @!method alert(msg, prefix = nil)
    #   Log a message at the alert priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    # @!method crit(msg, prefix = nil)
    #   Log a message at the critical priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    # @!method err(msg, prefix = nil)
    #   Log a message at the error priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    # @!method warning(msg, prefix = nil)
    #   Log a message at the warning priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    # @!method notice(msg, prefix = nil)
    #   Log a message at the notice priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    # @!method info(msg, prefix = nil)
    #   Log a message at the info priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    # @!method debug(msg, prefix = nil)
    #   Log a message at the debug priority
    #   @param [String] msg the message
    #   @param [Array<String, nil>, nil] prefix more prefixes, after this logger's
    #   @return [void]
    #   @api private
    LOG_METHODS.each_with_index do |method, priority|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{method}(msg, prefix = nil) # def emerg(msg, prefix = nil)
          # Below the log level, so dropped before anything is formatted
          return if #{priority} > @level # return if 0 > @level

          line = "\#{prefix ? label(@names + prefix) : @label}\#{msg}"
          if @stdout
            $stdout.puts("[#{method}]: \#{line}") # $stdout.puts("[emerg]: ...")
            $stdout.flush
          end
          @sink[0].#{method}(line) # @sink[0].emerg(line)
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
      parent = @logger
      if parent.instance_of?(Logger)
        parent.reopen
      else
        @sink.replace([create_logger])
      end
    end

    # The position in {LOG_METHODS} of the least severe priority to log
    #
    # @return [Integer]
    #
    # @api private
    attr_reader :level

    # Whether messages are echoed to stdout too
    #
    # @return [Boolean, nil]
    #
    # @api private
    attr_reader :stdout

    # Where the messages go, which every logger made from this one shares
    #
    # It holds one LoggerAdapter, Syslog, or given logger, and reopen
    # replaces it.
    #
    # @return [Array<Object>]
    #
    # @api private
    attr_reader :sink

    # This logger's prefixes, its parents' first
    #
    # @return [Array<String, nil>]
    #
    # @api private
    attr_reader :names

    protected

    # Return the level, prefixes, stdout and sink of a new logger
    #
    # A logger made with a parent logger writes through it: the parent's
    # level still applies, and so do its prefixes. One made with anything
    # else writes to that, without prefixes.
    #
    # @param [Logger, LoggerAdapter, Syslog, Object] parent the :logger
    #   option, or the log file or syslog without one
    # @param [Integer] level the position in {LOG_METHODS} of the least
    #   severe priority the :log_level option allows
    #
    # @return [Array(Integer, Array<String, nil>, Boolean, Array<Object>)]
    #   the level, the prefixes, whether to echo to stdout, and the sink
    #
    # @api private
    def settings_from(parent, level)
      if parent.instance_of?(Logger)
        [[level, parent.level].min, parent.names + [@prefix], parent.stdout, parent.sink]
      else
        names = [] #: Array[String?]
        [level, names, @options[:stdout], [parent]]
      end
    end

    # Return the prefixes as they start a message, as in "[app:web] "
    #
    # @param [Array<String, nil>] names the prefixes, nil for none
    #
    # @return [String, nil] the prefixes, or nil without any, which reads as
    #   nothing in a message
    #
    # @api private
    def label(names)
      names = names.compact
      "[#{names.join(":")}] " unless names.empty?
    end

    # Return the position of a log level in {LOG_METHODS}
    #
    # @param [Symbol, String] level a priority's name, such as :info
    #
    # @return [Integer] 0 for emerg, up to 7 for debug
    #
    # @raise [ArgumentError] if it isn't a priority's name
    #
    # @api private
    def priority(level)
      index = LOG_METHODS.index { |method| method.to_s.eql?(level.to_s) }
      raise ArgumentError, "Unknown log_level #{level.inspect}. Use one of: #{LOG_METHODS.join(", ")}" unless index

      index
    end

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
        Syslog.open(@options[:identity] || "bluepilld", Syslog::LOG_PID, Syslog::LOG_LOCAL6)
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
      # A HUP reopens the log from a signal trap, where require raises
      # ThreadError, and syslog is loaded by then
      require "syslog" unless defined?(::Syslog)
    rescue LoadError
      message = "Bluepill logs to syslog unless log_file is set, but the syslog library " \
                "could not be loaded. Since Ruby 3.4 it's a separate gem, so add gem 'syslog' " \
                "to your Gemfile or set log_file."
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
