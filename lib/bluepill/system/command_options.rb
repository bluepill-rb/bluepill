# frozen_string_literal: true

module Bluepill
  module System
    # How a command runs: as which user and groups, in which directory,
    # with which environment and standard streams, and for how long
    #
    # Every option is nil unless it's given. Process#command_options makes
    # one from the process's attributes.
    #
    # @api private
    class CommandOptions
      # Return the user the command runs as
      #
      # @return [String, nil] the user's name
      #
      # @api private
      attr_reader :uid

      # Return the group the command runs as
      #
      # @return [String, nil] the group's name
      #
      # @api private
      attr_reader :gid

      # Return the groups the command joins, besides the user's own
      #
      # @return [Array<String>, nil] the groups' names
      #
      # @api private
      attr_reader :supplementary_groups

      # Return the directory the command runs in
      #
      # @return [String, nil]
      #
      # @api private
      attr_reader :working_dir

      # Return the environment variables the command gets
      #
      # @return [Hash{#to_s => #to_s}] the variables, empty when there are
      #   none
      #
      # @api private
      attr_reader :environment

      # Return the file a daemon's standard input reads
      #
      # @return [String, nil]
      #
      # @api private
      attr_reader :stdin

      # Return the file a daemon's standard output is appended to
      #
      # @return [String, nil]
      #
      # @api private
      attr_reader :stdout

      # Return the file a daemon's standard error is appended to
      #
      # @return [String, nil]
      #
      # @api private
      attr_reader :stderr

      # Return how long a command that runs until it finishes may run
      #
      # @return [Numeric, ActiveSupport::Duration, nil] the seconds, or nil
      #   to wait until it finishes
      #
      # @api private
      attr_reader :timeout

      # Describe how a command runs
      #
      # @param [String, nil] uid the user's name
      # @param [String, nil] gid the group's name
      # @param [Array<String>, nil] supplementary_groups more groups' names
      # @param [String, nil] working_dir the directory to run in
      # @param [Hash{#to_s => #to_s}, nil] environment the environment
      #   variables, or nil for none
      # @param [String, nil] stdin a daemon's standard input
      # @param [String, nil] stdout a daemon's standard output
      # @param [String, nil] stderr a daemon's standard error
      # @param [Numeric, ActiveSupport::Duration, nil] timeout the seconds a
      #   command that runs until it finishes may take
      #
      # @return [void]
      #
      # @api private
      def initialize(uid: nil, gid: nil, supplementary_groups: nil, working_dir: nil, environment: nil, stdin: nil, stdout: nil, stderr: nil, timeout: nil)
        @uid = uid
        @gid = gid
        @supplementary_groups = supplementary_groups
        @working_dir = working_dir
        @environment = environment || {}
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @timeout = timeout
      end

      # Return the options for a hook command
      #
      # They're these, with more environment variables and a timeout.
      #
      # @param [Hash{String => String}] env more environment variables
      # @param [Numeric, ActiveSupport::Duration] timeout the seconds the hook
      #   may take
      #
      # @return [CommandOptions]
      #
      # @api private
      def for_hook(env, timeout)
        self.class.new(**to_h, environment: environment.merge(env), timeout: timeout)
      end

      # Return the options as a Hash
      #
      # @return [Hash{Symbol => Object}] each option by name, nil when unset
      #
      # @api private
      def to_h
        {
          uid: uid, gid: gid, supplementary_groups: supplementary_groups, working_dir: working_dir,
          environment: environment, stdin: stdin, stdout: stdout, stderr: stderr, timeout: timeout
        }
      end
    end
  end
end
