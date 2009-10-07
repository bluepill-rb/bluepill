module Bluepill
  module ProcessConditions
    class Flapping
      PARAMS = [:times, :within, :retry_in]
      
      attr_accessor *PARAMS
      attr_reader :timeline
      
      def initialize(options = {})
        options.reverse_merge!(:times => 5, :within => 1, :retry_in => 5)
        
        options.each_pair do |name, val|
          instance_variable_set("@#{name}", val) if PARAMS.include?(name)
        end
        
        @timeline = Util::RotationalArray.new(@times)
        
        register_state_machine_callbacks
      end
      
      def run(pid)
        # We do not need to run anything for this check
        nil
      end
      
      def check(value)
        num_occurances = (@timeline.nitems == self.times)
        
        # The process has not flapped if we haven't encountered enough incidents
        return true unless num_occurances
        
        # Check if the incident happend within the timeframe
        duration = (@timeline.last - @timeline.first) <= self.within
        
        if num_occurances && duration
          puts "Flapping detected: %s within %s - %s = %s" % [@timeline.inspect, @timeline.last, @timeline.first, @timeline.last - @timeline.first]
          
          schedule_restart
          dispatch!(:stop)
          
          
          @timeline.clear
          
          # Indicate that the process did not pass the flapping check
          false 
        else
          true
        end
      end
      
      private
      
      def register_state_machine_callbacks
        this = self
        Process.register_state_callback do
          after_transition(:down => :up) do |process, transition|
            this.timeline << Time.now.to_i
            
            
            puts "%s -> %s Timeline: %s" % [transition.from_name, transition.to_name, this.timeline.inspect]
          end
        end
      end
    end
  end
end