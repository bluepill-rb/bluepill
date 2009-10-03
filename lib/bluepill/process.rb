module Bluepill
  class Process
    attr_reader :name
    attr_accessor :pid
    def initialize(name)
      self.name = name
      @watches = []
      @handlers = {}
      
      set_default_event_handlers
    end
    
    def transition(state)
      # Transition to this state
    end
    
    def checkup
      # events are handled on FIFO, returning false from an event handler halts the chain, transitions force halt the chain.
      @watches.each do |watch|
        # do stuff, what to do with the events?
      end
    end
    
    def clear_history!
      @watch.each { |watch| watch.clear_history! }
    end
      
    private
    def set_default_event_handlers
      @handlers[:start] = lambda do |process|
        process.transition :up
      end
      
      @handlers[:restart] = lambda do |process|
        process.transition :down
        process.clear_history!
        process.transition :up
      end
      
      @handlers[:stop] = lambda do |process|
        process.transition :down
      end
    end
  end
end
 