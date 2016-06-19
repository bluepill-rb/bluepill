module Bluepill
  module Triggers
    class Flapping < Bluepill::Trigger
      TRIGGER_STATES = [:starting, :restarting].freeze

      PARAMS = [:times, :within, :retry_in].freeze

      attr_accessor(*PARAMS)
      attr_reader :timeline

      def initialize(process, options = {})
        options.reverse_merge!(times: 5, within: 1, retry_in: 5)

        options.each_pair do |name, val|
          instance_variable_set("@#{name}", val) if PARAMS.include?(name)
        end

        @timeline = Util::RotationalArray.new(@times)
        super
      end

      def notify(transition)
        return unless TRIGGER_STATES.include?(transition.to_name)
        timeline << Time.now.to_i
        check_flapping
      end

      def reset!
        @timeline.clear
        super
      end

      def check_flapping
        # The process has not flapped if we haven't encountered enough incidents
        return unless @timeline.compact.length == times

        # Check if the incident happend within the timeframe
        return unless @timeline.last - @timeline.first <= within

        logger.info "Flapping detected: retrying in #{retry_in} seconds"

        schedule_event(:start, retry_in) unless retry_in.zero? # retry_in zero means "do not retry, ever"
        schedule_event(:unmonitor, 0)

        @timeline.clear

        # This will prevent a transition from happening in the process state_machine
        throw :halt
      end
    end
  end
end
