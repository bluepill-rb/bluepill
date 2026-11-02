# frozen_string_literal: true

module Bluepill
  module ProcessJournal
    # What a journal holds: pids, or process group ids
    #
    # @api private
    class Kind
      # Return what the journal's log calls an id
      #
      # @return [String] pid or pgid
      #
      # @api private
      attr_reader :name

      # Return what the cleanup's log calls an id's process
      #
      # @return [String] process or process group
      #
      # @api private
      attr_reader :label

      # Return what an id is multiplied by to signal it
      #
      # A negative id signals the whole process group.
      #
      # @return [Integer] 1 for pids, or -1 for process groups
      #
      # @api private
      attr_reader :sign

      # Describe a kind of journal
      #
      # @param [String] name what the journal's log calls an id
      # @param [String] label what the cleanup's log calls an id's process
      # @param [String] file_tag what the journal's filename says it holds
      # @param [Integer] sign what an id is multiplied by to signal it
      #
      # @return [void]
      #
      # @api private
      def initialize(name, label, file_tag, sign)
        @name = name
        @label = label
        @file_tag = file_tag
        @sign = sign
      end

      # Return the path of a process's journal of this kind
      #
      # @param [String] dir the journal directory
      # @param [#to_s] journal_name the process's name
      #
      # @return [String] the journal's path
      #
      # @api private
      def filename(dir, journal_name) = File.join(dir, ".bluepill_#{@file_tag}_journal.#{journal_name}")
    end
  end
end
