# -*- encoding: utf-8 -*-
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
      str = @events.reverse.map do |(event, reason, time)|
        "  #{event} at #{time.strftime(STRFTIME)} - #{reason || "unspecified"}"
      end.join("\n")

      "event history:\n#{str}"
    end
  end
end
