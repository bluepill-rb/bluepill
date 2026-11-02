# frozen_string_literal: true

require "fileutils"
require "bluepill/base_directory"
require "bluepill/system"
require "bluepill/process_journal/kind"
require "bluepill/process_journal/journal"
require "bluepill/process_journal/config"
require "bluepill/process_journal/entries"
require "bluepill/process_journal/cleanup"
require "bluepill/process_journal/lock"

module Bluepill
  # Remember the pids and process groups of the processes bluepill starts
  #
  # Each process has a pid journal and a process group journal, files in the
  # app's journal directory with one id a line. Before bluepill starts a
  # process, it kills whatever an earlier run left in that process's
  # journals. A process reaches its journals through ProcessJournal.for.
  #
  # A pid can belong to another process by then: after a reboot, or once
  # pids wrap around. So each line also has when the process started, and
  # bluepill only kills a pid that still belongs to a process that started
  # then. A process group whose leader has exited is only killed if it was
  # journaled since the machine booted. Lines without a start time, from
  # bluepill 0.1 and earlier, are only trusted if the journal was written
  # since the machine booted.
  #
  # Each app has a journal directory of its own, so two apps with a process
  # of the same name don't share a journal. Bluepill 0.1 and earlier kept
  # every app's journals in one directory, and those are still read and
  # cleared, so upgrading doesn't leave their processes behind.
  #
  # One daemon monitors one app, so the journal directories and the logger
  # are kept on the module, which extends Config, Entries, Cleanup and
  # Lock.
  #
  # @api private
  module ProcessJournal
    extend Config
    extend Entries
    extend Cleanup
    extend Lock

    # A pid journal's kind
    #
    # @api private
    PID = Kind.new("pid", "process", "pids", 1).freeze

    # A process group journal's kind
    #
    # @api private
    PGID = Kind.new("pgid", "process group", "pgids", -1).freeze
  end
end
