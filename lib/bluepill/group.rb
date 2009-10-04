module Bluepill
  class Group
    attr_accessor :name, :processes, :logger
    attr_accessor :process_logger
    
    def initialize(name, options = {})
      self.name = name
      self.processes = []
      self.logger = options[:logger]
      
      if self.logger
        logger_prefix = self.name ? "#{self.name}:" : nil
        self.process_logger = Bluepill::Logger.new(self.logger, logger_prefix) 
      end
    end
    
    def add_process(process)
      process.logger = self.process_logger
      self.processes << process
    end
    
    def tick
      self.processes.each do |process|
        process.tick
      end
    end
    
    def start
      self.processes.each do |process|
        process.dispatch!("start")
      end
    end
  end
end