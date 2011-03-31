module Bluepill
  class ProcessStatistics    
    STRFTIME = "%m/%d/%Y %H:%I:%S"

    # possibly persist this data.
    def initialize
      @events = Util::RotationalArray.new(10)
    end

    def record_event(event, reason)
      @events.push([event, reason, Time.now])
    end

    def to_s
      str = @events.reverse.collect do |(event, reason, time)|
        str << "  #{event} at #{time.strftime(STRFTIME)} - #{reason || "unspecified"}"
      end.join("\n")

      "event history:\n#{str}"
    end
  end
end
