module Bluepill
  class Trigger
    @implementations = {}
    def self.inherited(klass)
      @implementations[klass.name.split('::').last.underscore.to_sym] = klass
    end
    
    def self.[](name)
      @implementations[name]
    end

    attr_accessor :process, :logger, :mutex, :scheduled_events
    
    def initialize(process, options = {})
      self.process = process
      self.logger = options[:logger]
      self.mutex = Mutex.new
      self.scheduled_events = []
    end
    
    def notify(transition)
      raise "Implement in subclass"
    end
    
    def dispatch!(event)
      self.process.dispatch!(event)
    end
    
    def schedule_event(event, delay)
      # TODO: maybe wrap this in a ScheduledEvent class with methods like cancel
      thread = Thread.new(self) do |trigger|
        begin
          sleep delay.to_f
          trigger.logger.info("Retrying from flapping")
          trigger.process.dispatch!(event)
          trigger.mutex.synchronize do
            trigger.scheduled_events.delete_if { |_, thread| thread == Thread.current }
          end
        rescue StandardError => e
          trigger.logger.err(e)
          trigger.logger.err(e.backtrace.join("\n"))
        end
      end
      
      self.scheduled_events.push([event, thread])
    end
    
    def cancel_all_events
      self.mutex.synchronize do
        self.scheduled_events.each {|_, thread| thread.kill}
      end
    end
    
  end
end