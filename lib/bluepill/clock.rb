module Bluepill
  # The clock that times ticks, checks, grace times and flapping
  #
  # The system clock can jump, when NTP corrects it or someone sets it, so
  # a time between two readings of Time.now can come out too long, too
  # short or below zero. The monotonic clock only counts up, one second a
  # second.
  #
  # @api private
  module Clock
    # Return a reader of the monotonic clock, or of the system clock
    #
    # Process.clock_gettime, which Ruby 2.1 added, reads the monotonic clock.
    # Ruby 1.9.3 and 2.0, and JRuby 1.7, don't have it, so they read the
    # system clock, as bluepill 0.1.6 did. JRuby 9.0 has no :second unit, so
    # it reads the clock in seconds, as a Float, and drops the fraction.
    #
    # @param [Module] process the module with clock_gettime, if Ruby has it
    #
    # @return [Proc] a reader of the time, in whole seconds
    #
    # @api private
    def self.reader(process = ::Process)
      if process.respond_to?(:clock_gettime)
        -> { Integer(process.clock_gettime(::Process::CLOCK_MONOTONIC)) }
      else
        -> { Integer(Time.now) }
      end
    end

    # The reader of this Ruby's clock, chosen once
    #
    # @api private
    READER = reader

    # Return the clock's time, in whole seconds
    #
    # The monotonic clock counts from an arbitrary point, such as when the
    # machine booted, so a reading only means something next to another one.
    #
    # @return [Integer]
    #
    # @api private
    def self.now
      READER.call
    end
  end
end
