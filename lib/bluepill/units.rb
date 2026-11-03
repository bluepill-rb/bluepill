# frozen_string_literal: true

module Bluepill
  # The durations and sizes a config writes, such as 10.seconds and
  # 100.megabytes, as plain numbers of seconds and bytes
  #
  # Bluepill includes this module in Numeric, so a method that Numeric
  # already has comes first. A config that loads ActiveSupport, say by
  # loading a Rails app, gets ActiveSupport's versions, which bluepill
  # accepts too.
  #
  # @example
  #   process.start_grace_time = 10.seconds # => 10
  #   process.checks :mem_usage, below: 100.megabytes # => 104_857_600
  #
  # @api public
  module Units
    # The number of seconds in a minute
    MINUTE = 60
    # The number of seconds in an hour
    HOUR = 60 * MINUTE
    # The number of seconds in a day
    DAY = 24 * HOUR
    # The number of bytes in a kilobyte
    KILOBYTE = 1024
    # The number of bytes in a megabyte
    MEGABYTE = 1024 * KILOBYTE
    # The number of bytes in a gigabyte
    GIGABYTE = 1024 * MEGABYTE
    # The number of bytes in a terabyte
    TERABYTE = 1024 * GIGABYTE

    # Return this many seconds, in seconds
    #
    # @example
    #   10.seconds # => 10
    #
    # @return [Numeric] the number itself
    #
    # @api public
    def seconds = self
    alias_method :second, :seconds

    # Return this many minutes, in seconds
    #
    # @example
    #   2.minutes # => 120
    #
    # @return [Numeric] the number of seconds
    #
    # @api public
    def minutes = self * MINUTE
    alias_method :minute, :minutes

    # Return this many hours, in seconds
    #
    # @example
    #   1.hour # => 3600
    #
    # @return [Numeric] the number of seconds
    #
    # @api public
    def hours = self * HOUR
    alias_method :hour, :hours

    # Return this many days, in seconds
    #
    # @example
    #   1.day # => 86400
    #
    # @return [Numeric] the number of seconds
    #
    # @api public
    def days = self * DAY
    alias_method :day, :days

    # Return this many bytes, in bytes
    #
    # @example
    #   512.bytes # => 512
    #
    # @return [Numeric] the number itself
    #
    # @api public
    def bytes = self
    alias_method :byte, :bytes

    # Return this many kilobytes, in bytes
    #
    # @example
    #   600.kilobytes # => 614400
    #
    # @return [Numeric] the number of bytes
    #
    # @api public
    def kilobytes = self * KILOBYTE
    alias_method :kilobyte, :kilobytes

    # Return this many megabytes, in bytes
    #
    # @example
    #   100.megabytes # => 104857600
    #
    # @return [Numeric] the number of bytes
    #
    # @api public
    def megabytes = self * MEGABYTE
    alias_method :megabyte, :megabytes

    # Return this many gigabytes, in bytes
    #
    # @example
    #   1.gigabyte # => 1073741824
    #
    # @return [Numeric] the number of bytes
    #
    # @api public
    def gigabytes = self * GIGABYTE
    alias_method :gigabyte, :gigabytes

    # Return this many terabytes, in bytes
    #
    # @example
    #   1.terabyte # => 1099511627776
    #
    # @return [Numeric] the number of bytes
    #
    # @api public
    def terabytes = self * TERABYTE
    alias_method :terabyte, :terabytes
  end
end

# Numeric's own methods, such as ActiveSupport's, come before an included
# module's, so these never replace them
class Numeric
  include Bluepill::Units
end
