module Bluepill
  # Keeps a process's last few events, which bluepill status shows
  #
  # @api private
  class ProcessStatistics
    # How status shows each event's time
    STRFTIME = '%m/%d/%Y %H:%M:%S'.freeze

    # How many events are kept
    EVENTS_TO_PERSIST = 10

    # Return the recorded events, newest last
    #
    # @return [Util::RotationalArray<Array(Symbol, String, nil, Time)>] each
    #   event, its reason and its time
    #
    # @api private
    attr_reader :events

    # Create an empty event history
    #
    # @return [void]
    #
    # @api private
    def initialize
      @events = Util::RotationalArray.new(EVENTS_TO_PERSIST)
    end

    # Add an event to the history, with the time it happened
    #
    # @param [Symbol, String] event the event, such as :restart
    # @param [String, nil] reason why it happened
    #
    # @return [Util::RotationalArray<Array(Symbol, String, nil, Time)>] the
    #   history, newest last
    #
    # @api private
    def record_event(event, reason)
      events.push([event, reason, Time.now])
    end

    # Return the history as text, newest first, for bluepill status
    #
    # @return [String]
    #
    # @api private
    def to_s
      str = events.reverse.collect do |event, reason, time|
        "  #{event} at #{time.strftime(STRFTIME)} - #{reason || 'unspecified'}"
      end.join("\n")

      "event history:\n#{str}"
    end
  end
end
