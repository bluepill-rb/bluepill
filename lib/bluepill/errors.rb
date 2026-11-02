# frozen_string_literal: true

module Bluepill
  # An error that stops the bluepill command, with the status it exits with
  #
  # The library raises these, and bin/bluepill and {Bluepill.application}
  # rescue them, print the message, and exit with {#exit_status}.
  #
  # @api public
  class Error < StandardError
    # Return the status that the bluepill command exits with
    #
    # @example
    #   Bluepill::Error.new.exit_status # => 1
    #
    # @return [Integer] 1, unless a subclass says otherwise
    #
    # @api public
    def exit_status = 1
  end

  # A mistake in a pill file, such as a misspelled process attribute or two
  # processes with the same pid file
  #
  # Bluepill.application prints its {#location} before its message.
  #
  # @api public
  class ConfigError < Error
    # The real path of bluepill's lib directory, whose frames in a backtrace
    # aren't the pill file's
    LIBRARY_DIR = "#{File.realpath("../..", __FILE__)}/"

    # Return the status that the bluepill command exits with
    #
    # @example
    #   Bluepill::ConfigError.new.exit_status # => 6
    #
    # @return [Integer] 6
    #
    # @api public
    def exit_status = 6

    # Return the line of the pill file that the error comes from
    #
    # It's the first frame of the backtrace in a file outside {LIBRARY_DIR},
    # so the pill file's line wherever bluepill raised the error, or a line
    # of a file that the pill file loads.
    #
    # @example
    #   error.location # => "/etc/bluepill/app.pill.rb:5"
    #
    # @return [String, nil] the file and line, or nil for an error that
    #   wasn't raised from a file
    #
    # @api public
    def location
      frame = Array(backtrace_locations).find { |candidate| outside_library?(candidate) }
      "#{frame.path}:#{frame.lineno}" if frame
    end

    private

    # Return whether a frame is in a file outside {LIBRARY_DIR}
    #
    # A frame of eval'd code, or of Ruby's own internals, such as
    # <internal:kernel> or JRuby's Java classes, isn't in a file. Real paths
    # are compared, so a symlink to bluepill's lib is still its lib.
    #
    # @param [Thread::Backtrace::Location] frame the frame
    #
    # @return [Boolean]
    #
    # @api private
    def outside_library?(frame)
      # Ruby gives every frame a path
      path = frame.path #: String
      File.file?(path) && !File.realpath(path).start_with?(LIBRARY_DIR)
    end
  end

  # The daemon couldn't start, such as when it can't write its log file
  #
  # @api public
  class StartupError < Error
    # Return the status that the bluepill command exits with
    #
    # @example
    #   Bluepill::StartupError.new.exit_status # => 5
    #
    # @return [Integer] 5
    #
    # @api public
    def exit_status = 5
  end

  # A previous daemon for the application couldn't be stopped
  #
  # @api public
  class PreviousDaemonError < Error
    # Return the status that the bluepill command exits with
    #
    # @example
    #   Bluepill::PreviousDaemonError.new.exit_status # => 4
    #
    # @return [Integer] 4
    #
    # @api public
    def exit_status = 4
  end

  # A daemon for the application already answers on its socket
  #
  # @api public
  class AlreadyRunningError < Error
    # Return the status that the bluepill command exits with
    #
    # @example
    #   Bluepill::AlreadyRunningError.new.exit_status # => 7
    #
    # @return [Integer] 7
    #
    # @api public
    def exit_status = 7
  end

  # The CLI couldn't reach the daemon, or it didn't answer in time
  #
  # @api public
  class ConnectionError < Error
  end

  # The daemon runs another version of bluepill than the CLI
  #
  # @api public
  class VersionMismatchError < Error
  end

  # The CLI was given a command it doesn't know
  #
  # @api public
  class UnknownCommandError < Error
  end

  # The daemon answered a command with an error that it raised
  #
  # @api public
  class DaemonError < Error
    # The error that the daemon raised, unmarshaled
    #
    # @example
    #   Bluepill::DaemonError.new(RuntimeError.new("boom")).daemon_error
    #   # => #<RuntimeError: boom>
    #
    # @return [Exception]
    #
    # @api public
    attr_reader :daemon_error

    # Wrap an error that the daemon raised
    #
    # The message has the daemon's error and its backtrace.
    #
    # @example
    #   Bluepill::DaemonError.new(RuntimeError.new("boom")).message
    #   # => "Received error from server:\n#<RuntimeError: boom>"
    #
    # @param [Exception] daemon_error the error
    #
    # @return [void]
    #
    # @api public
    def initialize(daemon_error)
      @daemon_error = daemon_error
      super(["Received error from server:", daemon_error.inspect, *daemon_error.backtrace].join("\n"))
    end

    # Return the status that the bluepill command exits with
    #
    # @example
    #   Bluepill::DaemonError.new(RuntimeError.new("boom")).exit_status # => 8
    #
    # @return [Integer] 8
    #
    # @api public
    def exit_status = 8
  end
end
