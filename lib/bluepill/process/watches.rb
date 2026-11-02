# frozen_string_literal: true

module Bluepill
  class Process
    # The checks that run on a Process every interval, such as its memory
    # usage, and the events they ask it for
    #
    # Each watch runs on a thread of its own when it's due, and the events it
    # fires, such as a restart, go back to the process to dispatch.
    #
    # @api private
    class Watches
      include Enumerable

      no_events = [] #: Array[[Symbol, String]]

      # What run returns when no watch is due, made once, since most ticks
      # have none
      NO_EVENTS = no_events.freeze

      # Return the logger the watches write to
      #
      # @return [Logger, nil]
      #
      # @api private
      attr_reader :logger

      # Create an empty set of watches, which write to a logger
      #
      # @param [Logger, nil] logger the process's logger, which each watch
      #   added gets too
      #
      # @return [void]
      #
      # @api private
      def initialize(logger:)
        @logger = logger
        @watches = []
      end

      # Add a watch for a check, with the watches' logger
      #
      # @param [Symbol] name the check's name, such as :mem_usage
      # @param [Hash{Symbol => Object}] options the check's options
      #
      # @return [Watches] the watches
      #
      # @api private
      def add(name, **options) = self << ConditionWatch.new(name, **options, logger: logger)

      # Add a watch
      #
      # @param [ConditionWatch] watch the watch
      #
      # @return [Watches] the watches
      #
      # @api private
      def <<(watch)
        @watches << watch
        self
      end

      # Yield each watch
      #
      # @yieldparam [ConditionWatch] watch a watch
      #
      # @return [Array<ConditionWatch>] the watches
      #
      # @api private
      def each(&) = @watches.each(&)

      # Forget what the watches have read, as when the process changes state
      #
      # @return [void]
      #
      # @api private
      def clear_history! = each(&:clear_history!)

      # Run every watch that's due, and return the events they fire
      #
      # Each watch runs on a thread of its own, so a slow one doesn't hold up
      # the others. One that isn't due would do nothing, so it gets no
      # thread.
      #
      # @param [Integer] now the time, from Clock.now
      #
      # @yieldreturn [Integer, nil] the process's pid, read on each watch's
      #   thread
      #
      # @return [Array<(Symbol, String)>] each event, with the watch that
      #   fired it as the reason
      #
      # @api private
      def run(now)
        threads = [] #: Array[[ConditionWatch, Thread]]
        each do |watch|
          threads << [watch, Thread.new { watch.run(yield, now) }] if watch.due?(now)
        end
        # Most ticks have no watch due, and nothing to wait for
        threads.empty? ? NO_EVENTS : events(threads)
      end

      private

      # Wait for the watches' threads, and return the events they fired
      #
      # Each watch that fired events is logged with them.
      #
      # @param [Array<(ConditionWatch, Thread)>] threads each watch that ran,
      #   with its thread
      #
      # @return [Array<(Symbol, String)>] each event, with the watch that
      #   fired it as the reason
      #
      # @api private
      def events(threads)
        threads.each_with_object([]) do |(watch, thread), events|
          fired = thread.value #: Array[Symbol]
          next if fired.empty?

          logger.info "#{watch.name} dispatched: #{fired.join(",")}"
          fired.each do |event|
            events << [event, watch.to_s]
          end
        end
      end
    end
  end
end
