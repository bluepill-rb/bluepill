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
      process.logger = self.logger.prefix_with(process.name)
      self.processes << process
    end
    
    def tick
      self.processes.each do |process|
        process.tick
      end
    end

    # proxied events
    [:start, :unmonitor, :stop, :restart, :boot].each do |event|
      class_eval <<-END
        def #{event}(process_name = nil)
          threads = []
          affected = []
          self.processes.each do |process|
            next if process_name && process_name != process.name
            affected << [self.name, process.name].join(":")
            threads << Thread.new { process.handle_user_command("#{event}") }
          end
          threads.each { |t| t.join }
          affected
        end      
      END
    end
  end
end