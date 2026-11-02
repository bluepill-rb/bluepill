# frozen_string_literal: true

module Bluepill
  module ProcessJournal
    # Where the journals are, and the logger they write to
    #
    # Only the first app and logger are kept, since one daemon monitors one
    # app. ProcessJournal extends it.
    #
    # @api private
    module Config
      # Return the logger the journal writes to
      #
      # @return [Logger] the first logger that was set
      #
      # @api private
      attr_reader :logger

      # Return the directory the app's journals are in
      #
      # @return [String] the app's directory in the journals directory
      #
      # @api private
      attr_reader :journal_base_dir

      # Return the directory every app's journals were in before 0.2
      #
      # @return [String] the journals directory under bluepill's base dir
      #
      # @api private
      attr_reader :legacy_journal_dir

      # Set the logger the journal writes to, unless it already has one
      #
      # @param [Logger] new_logger the logger to use
      #
      # @return [Logger] the logger
      #
      # @api private
      def logger=(new_logger)
        @logger ||= new_logger
      end

      # Set the app's journal directory from bluepill's base dir, and create it
      #
      # Only the first base dir and app are kept. The directories are made
      # world-writable so processes that run as other users can lock their
      # journals.
      #
      # @param [String] base_dir bluepill's base directory
      # @param [#to_s] app_name the app's name
      #
      # @return [void]
      #
      # @api private
      def setup(base_dir, app_name)
        @legacy_journal_dir ||= BaseDirectory.new(base_dir).journals_dir
        @journal_base_dir ||= File.join(@legacy_journal_dir, app_name.to_s)
        journal_dirs.each do |dir|
          FileUtils.mkdir_p(dir)
          FileUtils.chmod(0o777, dir)
        end
      end

      # Return the directories a process's journals can be in
      #
      # @return [Array<String>] the app's, and then the one before 0.2
      #
      # @api private
      def journal_dirs = [journal_base_dir, legacy_journal_dir]
    end
  end
end
