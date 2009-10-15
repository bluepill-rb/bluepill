module Bluepill
  module Triggers
    class Flapping < Bluepill::Trigger
      TRIGGER_STATES = [
        [:up, :down],
        [:up, :restarting]
      ]
      
      PARAMS = [:times, :within, :retry_in]
      
      attr_accessor *PARAMS
      attr_reader :timeline
      
      def initialize(process, options = {})
        options.reverse_merge!(:times => 5, :within => 1, :retry_in => 5)
        
        options.each_pair do |name, val|
          instance_variable_set("@#{name}", val) if PARAMS.include?(name)
        end
        
        @timeline = Util::RotationalArray.new(@times)
        super
      end
      
      def notify(transition)
        if TRIGGER_STATES.include?([transition.from_name, transition.to_name])
          self.timeline << Time.now.to_i
          self.check_flapping
        end
      end

      def check_flapping
        num_occurances = (@timeline.nitems == self.times)
        
        # The process has not flapped if we haven't encountered enough incidents
        return unless num_occurances
        
        # Check if the incident happend within the timeframe
        duration = (@timeline.last - @timeline.first) <= self.within
        
        if duration
          self.logger.info "Flapping detected: retrying in #{self.retry_in} seconds"
          
          self.schedule_event(:start, self.retry_in)
          
          # this happens in the process' thread so we don't have to worry about concurrency issues with this event
          self.dispatch!(:stop)
          
          @timeline.clear
        end
      end
    end
  end
end