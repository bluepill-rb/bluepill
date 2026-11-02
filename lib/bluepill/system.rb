# frozen_string_literal: true

require "bluepill/system/ps"
require "bluepill/system/usage"
require "bluepill/system/files"
require "bluepill/system/commands"

module Bluepill
  # Read what the system says about its processes, and run commands
  #
  # This represents the system that bluepill is running on. It memoizes
  # the results of running ps each tick, so that every watch of every
  # process doesn't fork a ps of its own. Running ps and reading its table
  # is in System::Ps, asking about a process is in System::Usage, deleting
  # files is in System::Files, and running commands is in System::Commands
  # and System::Daemon. System only extends them.
  #
  # @api private
  module System
    extend Ps
    extend Usage
    extend Files
    extend Commands
    extend Daemon
  end
end
