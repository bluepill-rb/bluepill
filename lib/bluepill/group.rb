# frozen_string_literal: true

module Bluepill
  # The processes of an application that share a group name
  #
  # A config puts a process in a group with `process.group = "name"`.
  # Processes without one are in the application's nameless group. A
  # command such as `bluepill restart name` acts on every process in the
  # group.
  #
  # @api private
  class Group
    # Return the group's name
    #
    # @return [String, nil] the name, or nil for the application's nameless
    #   group
    #
    # @api private
    attr_accessor :name

    # Return the group's processes
    #
    # @return [Array<Process>] the processes
    #
    # @api private
    attr_accessor :processes

    # Return the group's logger, which its processes' loggers prefix
    #
    # @return [Logger] the logger
    #
    # @api private
    attr_accessor :logger

    # Return a logger for processes, which bluepill doesn't use
    #
    # @return [Object] whatever was set
    #
    # @api private
    attr_accessor :process_logger

    # The setting that says whether each command runs on a process without
    # waiting for it
    NOBLOCK = {
      start: :group_start_noblock,
      unmonitor: :group_unmonitor_noblock,
      stop: :group_stop_noblock,
      restart: :group_restart_noblock
    }.freeze

    # Create an empty group
    #
    # @param [String, nil] name the group's name, or nil for the nameless
    #   group
    # @param [Hash{Symbol => Object}] options the group's options, with
    #   :logger
    #
    # @return [void]
    #
    # @api private
    def initialize(name, options = {})
      self.name = name
      self.processes = []
      logger = options[:logger] #: Logger
      self.logger = logger
    end

    # Add a process, giving it a logger prefixed with its name
    #
    # @param [Process] process the process
    #
    # @return [Array<Process>] the group's processes
    #
    # @api private
    def add_process(process)
      process.logger = logger.prefix_with(process.name)
      processes << process
    end

    # Tick every process in the group
    #
    # @return [void]
    #
    # @api private
    def tick
      processes.each(&:tick)
    end

    # Set each process's state from whether it's running
    #
    # Bluepill does this once, when it loads the config.
    #
    # @return [void]
    #
    # @api private
    def determine_initial_state
      processes.each(&:determine_initial_state)
    end

    # Start the group's processes, or one of them
    #
    # Each process runs the command on a thread of its own. Unless it's set
    # to run it without blocking (group_start_noblock), the group waits for it
    # before going on to the next process.
    #
    # @param [String, nil] process_name the process to start, or nil for
    #   every process in the group
    #
    # @return [Array<String>] the processes it started, as group:process
    #
    # @api private
    def start(process_name = nil)
      send_user_command(:start, process_name)
    end

    # Stop monitoring the group's processes, or one of them
    #
    # Each process runs the command on a thread of its own. Unless it's set
    # to run it without blocking (group_unmonitor_noblock), the group waits for it
    # before going on to the next process.
    #
    # @param [String, nil] process_name the process to unmonitor, or nil
    #   for every process in the group
    #
    # @return [Array<String>] the processes it unmonitored, as group:process
    #
    # @api private
    def unmonitor(process_name = nil)
      send_user_command(:unmonitor, process_name)
    end

    # Stop the group's processes, or one of them
    #
    # Each process runs the command on a thread of its own. Unless it's set
    # to run it without blocking (group_stop_noblock), the group waits for it
    # before going on to the next process.
    #
    # @param [String, nil] process_name the process to stop, or nil for
    #   every process in the group
    #
    # @return [Array<String>] the processes it stopped, as group:process
    #
    # @api private
    def stop(process_name = nil)
      send_user_command(:stop, process_name)
    end

    # Restart the group's processes, or one of them
    #
    # Each process runs the command on a thread of its own. Unless it's set
    # to run it without blocking (group_restart_noblock), the group waits for it
    # before going on to the next process.
    #
    # @param [String, nil] process_name the process to restart, or nil for
    #   every process in the group
    #
    # @return [Array<String>] the processes it restarted, as group:process
    #
    # @api private
    def restart(process_name = nil)
      send_user_command(:restart, process_name)
    end

    # Return the status lines that bluepill status shows
    #
    # Without a process name, it's a line for each process (and each of its
    # children, for one with monitor_children), under the group's name. For
    # one process, it's its line and its event history.
    #
    # @param [String, nil] process_name the process to show, or nil for
    #   every process in the group
    #
    # @return [Array<String>] the lines, ending with an empty one
    #
    # @api private
    def status(process_name = nil)
      lines = [] #: Array[String]
      if process_name.nil?
        add_group_status(lines)
      else
        add_process_status(process_name, lines)
      end
      lines << ""
    end

    private

    # Run a user command on the group's processes, or one of them
    #
    # Each process runs it on a thread of its own. The group waits for each
    # one that blocks before going on to the next process, and for the rest
    # at the end.
    #
    # @param [Symbol] event :start, :unmonitor, :stop or :restart
    # @param [String, nil] process_name the process to run it on, or nil for
    #   every process in the group
    #
    # @return [Array<String>] the processes it ran on, as group:process
    #
    # @api private
    def send_user_command(event, process_name)
      threads = [] #: Array[Thread]
      affected = targets(process_name).collect do |process|
        noblock = noblock?(process, event)
        thread = start_user_command(process, event, noblock)
        noblock ? threads << thread : thread.join
        [name, process.name].join(":")
      end
      threads.each(&:join)
      affected
    end

    # Return the group's processes, or the one with a name
    #
    # @param [String, nil] process_name the process, or nil for every
    #   process in the group
    #
    # @return [Array<Process>]
    #
    # @api private
    def targets(process_name)
      return processes unless process_name

      processes.select { |process| process_name.eql?(process.name) }
    end

    # Log how a process runs a user command, and start it on a thread
    #
    # @param [Process] process the process
    # @param [Symbol] event the command
    # @param [Boolean] noblock whether the group goes on without waiting
    #   for it
    #
    # @return [Thread] the thread that runs it
    #
    # @api private
    def start_user_command(process, event, noblock)
      logger.debug("Command #{event} running in #{noblock ? "non-blocking" : "blocking"} mode.")
      Thread.new { process.handle_user_command(event) }
    end

    # Return whether a process runs a user command without the group waiting
    #
    # @param [Process] process the process
    # @param [Symbol] event the command
    #
    # @return [Boolean]
    #
    # @api private
    def noblock?(process, event)
      process.public_send(NOBLOCK.fetch(event))
    end

    # Return a process's status line
    #
    # @param [Process] process the process
    # @param [String, nil] prefix the indent, if any
    #
    # @return [String] its name, pid and state
    #
    # @api private
    def status_line(process, prefix = nil)
      "#{prefix}#{process.name}(pid:#{process.actual_pid}): #{process.state}"
    end

    # Add a status line for each process, under the group's name
    #
    # A process with monitor_children has a line for each of its children
    # too.
    #
    # @param [Array<String>] lines the status lines to add to
    #
    # @return [void]
    #
    # @api private
    def add_group_status(lines)
      prefix = ("  " if name)
      lines << "#{name}:" if name

      processes.each do |process|
        lines << status_line(process, prefix)
        add_children_status(process.children, prefix, lines) if process.monitor_children?
      end
    end

    # Add a status line for each child of a process
    #
    # @param [Array<Process>] children the process's children
    # @param [String, nil] prefix the indent of the process's line
    # @param [Array<String>] lines the status lines to add to
    #
    # @return [void]
    #
    # @api private
    def add_children_status(children, prefix, lines)
      children.each do |child|
        lines << "  #{prefix}#{child.name}: #{child.state}"
      end
    end

    # Add a process's status line and its event history
    #
    # @param [String] process_name the process to show
    # @param [Array<String>] lines the status lines to add to
    #
    # @return [void]
    #
    # @api private
    def add_process_status(process_name, lines)
      processes.each do |process|
        next unless process_name.eql?(process.name)

        lines << status_line(process)
        lines << process.statistics.to_s
      end
    end
  end
end
