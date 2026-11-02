# frozen_string_literal: true

require "set"

module Bluepill
  class ProcessFactory
    # The process names and pid files that an application's config has used
    #
    # Each {AppProxy} keeps one and hands it to the factory of each of its
    # processes, so the factories can catch two processes with the same name
    # in a group, or the same pid file. An application that loads again
    # starts with an empty registry.
    #
    # @api private
    class Registry
      # Create an empty registry
      #
      # @return [void]
      #
      # @api private
      def initialize
        @process_keys = Set.new #: Set[[String?, String]]
        @pid_files = Set.new #: Set[String]
      end

      # Add a process's name in its group, unless it's there already
      #
      # A process name may contain ':', so the key keeps the group and the
      # name apart. Like Application#add_process, it treats Symbols and
      # Strings alike.
      #
      # @param [#to_s, nil] group the process's group, or nil for none
      # @param [#to_s] name the process's name
      #
      # @return [Boolean] true for a new name, false for one already added
      #
      # @api private
      def add_process?(group, name) = !@process_keys.add?([group&.to_s, name.to_s]).nil?

      # Add a pid file, unless it's there already
      #
      # @param [String] pid_file the pid file
      #
      # @return [Boolean] true for a new pid file, false for one already
      #   added
      #
      # @api private
      def add_pid_file?(pid_file) = !@pid_files.add?(pid_file).nil?
    end
  end
end
