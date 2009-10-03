module BluePill
  class ProcessStateMachine
    def initialize(process)
      @process = process
      @current_state = :init
    end
    
    def up
    end
    
    def down
    end
  end
end