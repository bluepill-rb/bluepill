module Bluepill
  class Process
    # Runs what a Process does on its way from one state to another
    #
    # Before a transition, the triggers hear of it. After it, the process is
    # started, stopped or restarted for the state it reached, its watches
    # forget what they read, and its hooks run.
    #
    # @api private
    module TransitionCallbacks
      # The states that a start or restart moves a process through on its
      # way up, after which post_start_command runs
      STARTS = %i[starting restarting].freeze

      # Run the callbacks before a transition
      #
      # They tell the triggers, and clean up the threads of a stop on the way
      # out of stopping.
      #
      # @param [Transition] transition the move about to happen
      #
      # @return [true] so fire_event knows no callback halted
      #
      # @api private
      def before_transition(transition)
        notify_triggers(transition)
        clean_threads if transition.from_name.equal?(:stopping)
        true
      end

      # Run the callbacks after a transition
      #
      # They start, stop or restart the process for the state it reached, and
      # then record the transition. Then they run post_start_command when a
      # start or restart brought the process up, and notify_command when its
      # state changed, in that order, as state_machine ran them.
      #
      # @param [Transition] transition the move that happened
      #
      # @return [void]
      #
      # @api private
      def after_transition(transition)
        case transition.to_name
        when :starting then start_process
        when :stopping then stop_process
        when :restarting then restart_process
        end
        record_transition(transition)
        post_start_process if transition.to_name.equal?(:up) && STARTS.include?(transition.from_name)
        notify_transition(transition)
      end

      # Tell every trigger about a transition
      #
      # @param [#from_name, #to_name, #loopback?] transition the transition
      #
      # @return [void]
      #
      # @raise [StandardError] what a trigger raised, after logging it
      #
      # @api private
      def notify_triggers(transition)
        triggers.each do |trigger|
          begin
            trigger.notify(transition)
          rescue => e
            logger.err e.backtrace
            raise
          end
        end
      end

      # Clear the watches' history after the process changes state
      #
      # A process that's monitoring its children also clears their list, so it
      # finds them again. A loopback, such as up to up, changes nothing.
      #
      # @param [#from_name, #to_name, #loopback?] transition the transition
      #
      # @return [void]
      #
      # @api private
      def record_transition(transition)
        return if transition.loopback?

        @transitioned = true

        # When a process changes state, we should clear the memory of all the watches
        watches.clear_history!

        # Also, when a process changes state, we should re-populate its child list
        if monitor_children?
          logger.warning "Clearing child list"
          children.clear
        end
        logger.info "Going from #{transition.from_name} => #{transition.to_name}"
      end
    end
  end
end
