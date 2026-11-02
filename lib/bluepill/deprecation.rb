module Bluepill
  # Warns, once each, about what a later version of bluepill will change
  #
  # A warning goes to stderr, where `bluepill load` shows it, since the pill
  # file loads before the daemon detaches, and to bluepill's log once
  # there is one. Each key warns once per process, so a warning raised
  # while the daemon runs doesn't fill the log.
  #
  # @example
  #   Bluepill::Deprecation.warn(:pre_start_command, 'bluepill 0.2.0 ...')
  #
  # @api private
  module Deprecation
    @warned = {}
    @mutex = Mutex.new
    @logger = nil

    class << self
      # The logger that warnings also go to, once bluepill has one
      #
      # The application sets it when it creates its logger.
      #
      # @return [Logger, nil]
      #
      # @api private
      attr_accessor :logger
    end

    # Warn about a change, unless this key has warned already
    #
    # @param [Object] key what the warning is about, such as
    #   :pre_start_command
    # @param [String] message what will change, in which version, and what
    #   to do now
    #
    # @return [Boolean] whether it warned
    #
    # @api private
    def self.warn(key, message)
      return false unless first?(key)

      line = "DEPRECATION: #{message}"
      $stderr.puts(line)
      log = logger
      log.warning(line) if log
      true
    end

    # Return whether a key is warning for the first time, and remember it
    #
    # @param [Object] key what the warning is about
    #
    # @return [Boolean] true the first time for each key
    #
    # @api private
    def self.first?(key)
      @mutex.synchronize do
        return false if @warned.key?(key)

        @warned[key] = true
      end
    end

    # Forget the warnings given, and the logger, as between specs
    #
    # @return [void]
    #
    # @api private
    def self.reset!
      @mutex.synchronize { @warned.clear }
      self.logger = nil
    end
  end
end
