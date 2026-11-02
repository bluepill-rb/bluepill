# frozen_string_literal: true

module Bluepill
  # A mistake in a pill file, such as a misspelled process attribute or two
  # processes with the same pid file
  #
  # Bluepill.application prints its message and exits with status 6.
  #
  # @api public
  class ConfigError < StandardError
  end
end
