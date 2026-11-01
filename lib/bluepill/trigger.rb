module Bluepill
  class Trigger
    @implementations = {}
    def self.inherited(klass)
      super
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

    def reset!
      cancel_all_events
    end

    def notify(_transition)
      raise 'Implement in subclass'
    end

    def dispatch!(event)
      process.dispatch!(event, self.class.name.split('::').last)
    end

    # Dispatches event after delay seconds in a new thread, and returns it
    def schedule_event(event, delay)
      mutex.synchronize do
        thread = Thread.new(self) do |trigger|
          begin
            sleep delay.to_f
            trigger.dispatch!(event)
            trigger.mutex.synchronize do
              trigger.scheduled_events.delete_if { |_, t| t == Thread.current }
            end
          rescue StandardError => e
            trigger.logger.err(e)
            trigger.logger.err(e.backtrace.join("\n"))
          end
        end
        scheduled_events.push([event, thread])
        thread
      end
    end

    def cancel_all_events
      logger.info 'Canceling all scheduled events'
      mutex.synchronize do
        scheduled_events.collect(&:last).each(&:kill)
        scheduled_events.clear
      end
    end
  end
end
