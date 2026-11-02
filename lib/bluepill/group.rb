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

    # @!method start(process_name = nil)
    #   Start the group's processes, or one of them
    #
    #   Each process runs the command on a thread of its own. Unless it's
    #   set to run it without blocking (group_start_noblock), the group
    #   waits for it before going on to the next process.
    #
    #   @param [String, nil] process_name the process to start, or nil for
    #     every process in the group
    #
    #   @return [Array<String>] the processes it started, as group:process
    #
    #   @api private
    #
    # @!method unmonitor(process_name = nil)
    #   Stop monitoring the group's processes, or one of them
    #
    #   Each process runs the command on a thread of its own. Unless it's
    #   set to run it without blocking (group_unmonitor_noblock), the group
    #   waits for it before going on to the next process.
    #
    #   @param [String, nil] process_name the process to unmonitor, or nil
    #     for every process in the group
    #
    #   @return [Array<String>] the processes it unmonitored, as
    #     group:process
    #
    #   @api private
    #
    # @!method stop(process_name = nil)
    #   Stop the group's processes, or one of them
    #
    #   Each process runs the command on a thread of its own. Unless it's
    #   set to run it without blocking (group_stop_noblock), the group waits
    #   for it before going on to the next process.
    #
    #   @param [String, nil] process_name the process to stop, or nil for
    #     every process in the group
    #
    #   @return [Array<String>] the processes it stopped, as group:process
    #
    #   @api private
    #
    # @!method restart(process_name = nil)
    #   Restart the group's processes, or one of them
    #
    #   Each process runs the command on a thread of its own. Unless it's
    #   set to run it without blocking (group_restart_noblock), the group
    #   waits for it before going on to the next process.
    #
    #   @param [String, nil] process_name the process to restart, or nil for
    #     every process in the group
    #
    #   @return [Array<String>] the processes it restarted, as group:process
    #
    #   @api private
    [:start, :unmonitor, :stop, :restart].each do |event|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{event}(process_name = nil) # def start(process_name = nil)
          threads = []
          affected = []
          self.processes.each do |process|
            next if process_name && process_name != process.name
            affected << [self.name, process.name].join(":")
            noblock = process.group_#{event}_noblock # process.group_start_noblock
            if noblock
              self.logger.debug("Command #{event} running in non-blocking mode.") # Command start running in...
              threads << Thread.new { process.handle_user_command("#{event}") } # handle_user_command("start")
            else
              self.logger.debug("Command #{event} running in blocking mode.") # Command start running in...
              thread = Thread.new { process.handle_user_command("#{event}") } # handle_user_command("start")
              thread.join
            end
          end
          threads.each { |t| t.join } unless threads.nil?
          affected
        end
      RUBY
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
        prefix = ('  ' if name)
        lines << "#{name}:" if name

        processes.each do |process|
          lines << format('%s%s(pid:%s): %s', prefix, process.name, process.actual_pid, process.state)
          next unless process.monitor_children?

          process.children.each do |child|
            lines << format('  %s%s: %s', prefix, child.name, child.state)
          end
        end

      else
        processes.each do |process|
          next unless process_name.eql?(process.name)

          lines << format('%s(pid:%s): %s', process.name, process.actual_pid, process.state)
          lines << process.statistics.to_s
        end
      end
      lines << ''
    end
  end
end
