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
      str = []
      @events.each do |(event, reason, time)|
        str << "  #{event} at #{time.strftime(STRFTIME)} - #{reason || "unspecified"}"
      end
      if str.size > 0
        str << "event history:"
      end
      str.reverse.join("\n")
    end
  end
end
