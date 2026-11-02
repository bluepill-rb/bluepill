# frozen_string_literal: true

module Bluepill
  module Util
    # Log an error at err, with a line of its own for each backtrace line
    #
    # The daemon rescues what a check, a trigger or a tick raises, so the
    # log is the only place the error shows.
    #
    # @example
    #   Bluepill::Util.log_error(logger, "mem_usage check failed", error)
    #   # mem_usage check failed: RuntimeError: boom
    #   # /path/to/check.rb:12:in `run'
    #
    # @param [Logger] logger the logger to write to
    # @param [String] summary what failed, which the error's class and
    #   message follow
    # @param [Exception] error the error
    #
    # @return [void]
    #
    # @api private
    def self.log_error(logger, summary, error)
      logger.err("#{summary}: #{error.class}: #{error}")
      error.backtrace&.each { |line| logger.err(line) }
    end
  end
end
