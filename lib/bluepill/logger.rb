# frozen_string_literal: true

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
    LOG_METHODS = %i[emerg alert crit err warning notice info debug].freeze

    # Make a logger without prefixes
    #
    # prefix_with makes the loggers that add prefixes.
    #
    # @param [Object, nil] logger the backend to write to, which answers to
    #   the {LOG_METHODS}, or nil for the log file or syslog
    # @param [Boolean] stdout whether to echo messages to stdout too
    # @param [String, nil] log_file the file to write to instead of syslog
    # @param [String] identity the name syslog shows
    # @param [Symbol, String] log_level the least severe priority to log
    #   (debug, so everything, by default)
    #
    # @return [void]
    #
    # @raise [ArgumentError] if log_level isn't one of {LOG_METHODS}
    #
    # @api private
    def initialize(logger: nil, stdout: false, log_file: nil, identity: "bluepilld", log_level: :debug)
      @log_file = log_file
      @identity = identity
      @level = priority(log_level)
      @stdout = stdout
      @names = [] #: Array[String?]
      @label = nil
      # A box, not the backend itself, so that reopen can swap the backend
      # for this logger and every logger that prefix_with makes from it
      @sink = [logger || create_logger]
      @prefixes = {}
    end

    # @!method emerg(msg)
    #   Log a message at the emergency priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    # @!method alert(msg)
    #   Log a message at the alert priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    # @!method crit(msg)
    #   Log a message at the critical priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    # @!method err(msg)
    #   Log a message at the error priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    # @!method warning(msg)
    #   Log a message at the warning priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    # @!method notice(msg)
    #   Log a message at the notice priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    # @!method info(msg)
    #   Log a message at the info priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    # @!method debug(msg)
    #   Log a message at the debug priority
    #   @param [String] msg the message
    #   @return [void]
    #   @api private
    LOG_METHODS.each_with_index do |method, priority|
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def #{method}(msg) # def emerg(msg)
          # Below the log level, so dropped before anything is formatted
          return if #{priority} > @level # return if 0 > @level

          line = "\#{@label}\#{msg}"
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
    # It's a copy of this logger, so it has the same level and echoes to
    # stdout if this one does, and it shares the sink. It's made once for
    # each prefix, and kept.
    #
    # @param [String, nil] prefix the prefix, such as a process's name, or
    #   nil for none
    #
    # @return [Logger] the prefixed logger
    #
    # @api private
    def prefix_with(prefix) = @prefixes[prefix] ||= dup.add_prefix(prefix)

    # Open the log file or syslog again, such as after log rotation
    #
    # Every logger made from the same one shares the sink, so they all
    # write to the new one.
    #
    # @return [void]
    #
    # @api private
    def reopen = @sink.replace([create_logger])

    protected

    # Add a prefix to a copy of a logger, which prefix_with made
    #
    # The copy gets its own prefixes and prefixed loggers, so the logger it
    # copies keeps its own.
    #
    # @param [String, nil] prefix the prefix, or nil for none
    #
    # @return [Logger] the copy
    #
    # @api private
    def add_prefix(prefix)
      @names += [prefix]
      @label = label(@names)
      @prefixes = {}
      self
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
      log_file = @log_file
      if log_file
        LoggerAdapter.new(log_file)
      else
        require_syslog
        Syslog.close if Syslog.opened? # need to explictly close it before reopening it
        Syslog.open(@identity, Syslog::LOG_PID, Syslog::LOG_LOCAL6)
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
      LOGGER_EQUIVALENTS = {
        debug: :debug,
        err: :error,
        warning: :warn,
        info: :info,
        emerg: :fatal,
        alert: :warn,
        crit: :fatal,
        notice: :info
      }.freeze

      LOG_METHODS.each do |method|
        next if method == LOGGER_EQUIVALENTS[method]

        alias_method method, LOGGER_EQUIVALENTS[method]
      end
    end
  end
end
