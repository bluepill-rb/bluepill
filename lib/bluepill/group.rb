module Bluepill
  class Group
    attr_accessor :name, :processes, :logger
    attr_accessor :process_logger

    def initialize(name, options = {})
      self.name = name
      self.processes = []
      self.logger = options[:logger]
    end

    def add_process(process)
      process.logger = logger.prefix_with(process.name)
      processes << process
    end

    def tick
      processes.each(&:tick)
    end

    def determine_initial_state
      processes.each(&:determine_initial_state)
    end

    # proxied events
    [:start, :unmonitor, :stop, :restart].each do |event|
      class_eval <<-END
        def #{event}(process_name = nil)
          threads = []
          affected = []
          self.processes.each do |process|
            next if process_name && process_name != process.name
            affected << [self.name, process.name].join(":")
            noblock = process.group_#{event}_noblock
            if noblock
              self.logger.debug("Command #{event} running in non-blocking mode.")
              threads << Thread.new { process.handle_user_command("#{event}") }
            else
              self.logger.debug("Command #{event} running in blocking mode.")
              thread = Thread.new { process.handle_user_command("#{event}") }
              thread.join
            end
          end
          threads.each { |t| t.join } unless threads.nil?
          affected
        end
      END
    end

    def status(process_name = nil)
      lines = []
      if process_name.nil?
        prefix = name ? '  ' : ''
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
          next if process_name != process.name
          lines << format('%s%s(pid:%s): %s', prefix, process.name, process.actual_pid, process.state)
          lines << process.statistics.to_s
        end
      end
      lines << ''
    end
  end
end
