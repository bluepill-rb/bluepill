module Bluepill
  class Trigger
    @implementations = {}
    def self.inherited(klass)
      @implementations[klass.name.split('::').last.underscore.to_sym] = klass
    end
    
    def self.[](name)
      @implementations[name]
    end

    attr_accessor :process, :logger
    
    def initialize(process, options = {})
      self.process = process
      self.logger = options[:logger]
    end
    
    def notify(transition)
      raise "Implement in subclass"
    end
    
    def dispatch!(event)
      self.process.dispatch!(event)
    end
    
    def schedule_event(event, delay)
      # TODO: maybe wrap this in a ScheduledEvent class with methods like cancel
      Thread.new do
        sleep delay
        self.logger.info("Retrying from flapping")
        process.dispatch!(event)
      end
    end
    
  end
end