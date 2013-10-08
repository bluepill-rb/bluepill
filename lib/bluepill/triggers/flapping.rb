# -*- encoding: utf-8 -*-
module Bluepill
  module Triggers
    class Flapping < Bluepill::Trigger
      TRIGGER_STATES = [:starting, :restarting]

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
        if TRIGGER_STATES.include?(transition.to_name)
          self.timeline << Time.now.to_i
          self.check_flapping
        end
      end

      def reset!
        @timeline.clear
        super
      end

      def check_flapping
        # The process has not flapped if we haven't encountered enough incidents
        return unless (@timeline.compact.length == self.times)

        # Check if the incident happend within the timeframe
        duration = (@timeline.last - @timeline.first) <= self.within

        if duration
          self.logger.info "Flapping detected: retrying in #{self.retry_in} seconds"

          self.schedule_event(:start, self.retry_in) unless self.retry_in == 0 # retry_in zero means "do not retry, ever"
          self.schedule_event(:unmonitor, 0)

          @timeline.clear

          # This will prevent a transition from happening in the process state_machine
          throw :halt
        end
      end
    end
  end
end
