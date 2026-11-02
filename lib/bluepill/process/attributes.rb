# frozen_string_literal: true

module Bluepill
  class Process
    # The options a config can set for a Process, and their defaults
    #
    # @api private
    module Attributes
      # The options a config can set for a process
      CONFIGURABLE_ATTRIBUTES = %i[
        pre_start_command
        start_command
        stop_command
        restart_command

        post_start_command
        pre_stop_command
        post_stop_command
        notify_command
        hook_timeout

        stdout
        stderr
        stdin

        daemonize
        pid_file
        working_dir
        environment

        start_grace_time
        stop_grace_time
        restart_grace_time

        uid
        gid

        cache_actual_pid

        monitor_children
        child_process_factory

        pid_command
        auto_start

        supplementary_groups

        stop_signals

        on_start_timeout

        group_start_noblock
        group_restart_noblock
        group_stop_noblock
        group_unmonitor_noblock
      ].freeze

      # Return the command run before every start, if any
      #
      # Bluepill waits for it to finish, and starts the process even if it exits
      # with a non-zero status. It runs in the process's working_dir, with its
      # environment, uid and gid.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :pre_start_command

      # Return the command that starts the process
      #
      # Bluepill splits it into words and runs it without a shell.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :start_command

      # Return the command run each time the process comes up after a start
      #
      # It runs when the process reaches up, after a start or a restart, so a
      # server that daemonizes itself has written its pid file by then.
      # <tt>{{PID}}</tt> in it is replaced with the process's pid. It runs in
      # the background, and a failure is only logged.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :post_start_command

      # Return the command run before the process is stopped, if any
      #
      # The stop waits for it to finish, for up to hook_timeout, when it's
      # killed, and then goes ahead either way. <tt>{{PID}}</tt> in it is replaced with the
      # process's pid.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :pre_stop_command

      # Return the command run after the process has stopped, if any
      #
      # It runs in the background once bluepill has cleaned up after the
      # process. <tt>{{PID}}</tt> in it is replaced with the pid that stopped.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :post_stop_command

      # Return the command run each time the process changes state, if any
      #
      # It runs in the background, with BLUEPILL_APP, BLUEPILL_GROUP,
      # BLUEPILL_PROCESS, BLUEPILL_FROM, BLUEPILL_TO, BLUEPILL_REASON and
      # BLUEPILL_PID in its environment. An app can set it for all its
      # processes.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :notify_command

      # Return how long a hook command may run before bluepill kills it
      #
      # It applies to post_start_command, pre_stop_command, post_stop_command
      # and notify_command. The default is 30 seconds.
      #
      # @return [Integer, Float]
      #
      # @api private
      attr_accessor :hook_timeout

      # Return the command that stops the process, if any
      #
      # <tt>{{PID}}</tt> in it is replaced with the process's pid. Without
      # one, bluepill sends stop_signals, or TERM.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :stop_command

      # Return the command that restarts the process, if any
      #
      # <tt>{{PID}}</tt> in it is replaced with the process's pid. Without
      # one, bluepill stops the process and starts it again.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :restart_command

      # Return the file a daemonized process's standard output goes to
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :stdout

      # Return the file a daemonized process's standard error goes to
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :stderr

      # Return the file a daemonized process's standard input comes from
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :stdin

      # Return whether bluepill daemonizes the process and writes its pid file
      #
      # Set it for a process that doesn't daemonize itself.
      #
      # @return [Boolean, nil]
      #
      # @api private
      attr_accessor :daemonize

      # Return the file that holds the process's pid
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :pid_file

      # Return the directory the process's commands run in
      #
      # A daemonized process starts in / unless this is set.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :working_dir

      # Return the environment variables the process's commands get
      #
      # @return [Hash{#to_s => #to_s}, nil]
      #
      # @api private
      attr_accessor :environment

      # Return how long to wait for the process to start, in seconds
      #
      # Bluepill skips ticks for this long after a start. The default is 3.
      #
      # @return [Integer, Float]
      #
      # @api private
      attr_accessor :start_grace_time

      # Return how long to wait for the process to stop, in seconds
      #
      # Bluepill skips ticks for this long after a stop. The default is 3.
      #
      # @return [Integer, Float]
      #
      # @api private
      attr_accessor :stop_grace_time

      # Return how long to wait for the process to restart, in seconds
      #
      # Bluepill skips ticks for this long after a restart. The default is 3.
      #
      # @return [Integer, Float]
      #
      # @api private
      attr_accessor :restart_grace_time

      # Return the user the process's commands run as
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :uid

      # Return the group the process's commands run as
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :gid

      # Return whether to read the pid file only until it gives a pid
      #
      # True by default. Set it to false for a process whose pid changes, such
      # as one checked for zombies.
      #
      # @return [Boolean]
      #
      # @api private
      attr_accessor :cache_actual_pid

      # Return whether bluepill also watches the process's children
      #
      # @return [Boolean]
      #
      # @api private
      attr_accessor :monitor_children

      # Return the factory that makes a Process for each child found
      #
      # monitor_children sets it, with the children's checks.
      #
      # @return [ProcessFactory, nil]
      #
      # @api private
      attr_accessor :child_process_factory

      # Return the command whose output is the process's pid, if any
      #
      # Used instead of pid_file when it's set.
      #
      # @return [String, nil]
      #
      # @api private
      attr_accessor :pid_command

      # Return whether bluepill starts the process when it loads
      #
      # Only false keeps it from starting: the process is then unmonitored.
      #
      # @return [Boolean, nil]
      #
      # @api private
      attr_accessor :auto_start

      # Return the extra groups the process's commands run with
      #
      # @return [Array<String>, nil]
      #
      # @api private
      attr_accessor :supplementary_groups

      # Return the signals that stop the process, with the delays between
      #
      # A signal, then a delay in seconds and a signal, and so on, such as
      # [:quit, 30, :term, 5, :kill]. Each later signal is only sent if the
      # process is still running.
      #
      # @return [Array<Symbol, Integer>, nil]
      #
      # @api private
      attr_accessor :stop_signals

      # Return the event to dispatch when the start command takes too long
      #
      # The default is start, which tries again.
      #
      # @return [String, Symbol]
      #
      # @api private
      attr_accessor :on_start_timeout

      # Return whether a group's start runs without waiting for this process
      #
      # @return [Boolean]
      #
      # @api private
      attr_accessor :group_start_noblock

      # Return whether a group's restart runs without waiting for this process
      #
      # @return [Boolean]
      #
      # @api private
      attr_accessor :group_restart_noblock

      # Return whether a group's stop runs without waiting for this process
      #
      # @return [Boolean]
      #
      # @api private
      attr_accessor :group_stop_noblock

      # Return whether a group's unmonitor runs without waiting for it
      #
      # @return [Boolean]
      #
      # @api private
      attr_accessor :group_unmonitor_noblock

      # Set the defaults, and then the options the config gives
      #
      # @param [Hash{Symbol => Object}] options the process's options, of
      #   which those in CONFIGURABLE_ATTRIBUTES are set
      #
      # @return [void]
      #
      # @api private
      def configure(options)
        apply_defaults
        CONFIGURABLE_ATTRIBUTES.each do |attribute_name|
          public_send("#{attribute_name}=", options.fetch(attribute_name)) if options.key?(attribute_name)
        end
      end

      # Set the defaults of the options that have one
      #
      # The grace times are 3 seconds, hooks get 30, the pid is cached,
      # children are left alone, and a group doesn't wait for the process.
      #
      # @return [void]
      #
      # @api private
      def apply_defaults
        # These defaults are overriden by configure if it's configured to be something else.
        @monitor_children = false
        @cache_actual_pid = true
        @start_grace_time = @stop_grace_time = @restart_grace_time = 3
        @environment = {}
        @on_start_timeout = "start"
        @hook_timeout = 30
        @group_start_noblock = @group_stop_noblock = @group_restart_noblock = @group_unmonitor_noblock = true
      end
    end
  end
end
