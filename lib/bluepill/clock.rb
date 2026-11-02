# frozen_string_literal: true

module Bluepill
  # The clock that times ticks, checks and grace times
  #
  # The system clock can jump, when NTP corrects it or someone sets it, so
  # a time between two readings of Time.now can come out too long, too
  # short or below zero. The monotonic clock only counts up, one second a
  # second.
  #
  # @api private
  module Clock
    # Return the monotonic clock's time, in whole seconds
    #
    # It counts from an arbitrary point, such as when the machine booted, so
    # a reading only means something next to another one. JRuby 9.0 has no
    # :second unit, so it reads the clock in seconds, as a Float, and drops
    # the fraction.
    #
    # @return [Integer]
    #
    # @api private
    def self.now
      Integer(::Process.clock_gettime(::Process::CLOCK_MONOTONIC))
    end
  end
end
