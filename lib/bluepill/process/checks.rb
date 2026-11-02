module Bluepill
  class Process
    # Runs a Process's watches, and tells its triggers about its transitions
    #
    # Watches check the process every interval and fire events, such as a
    # restart when it uses too much memory. Triggers see every transition,
    # such as the flapping trigger that stops a process that keeps
    # restarting.
    #
    # @api private
    module Checks
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
        watches.each(&:clear_history!)

        # Also, when a process changes state, we should re-populate its child list
        if monitor_children?
          logger.warning "Clearing child list"
          children.clear
        end
        logger.info "Going from #{transition.from_name} => #{transition.to_name}"
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

      # Run every watch, and dispatch the events they fire
      #
      # Each watch runs in a thread of its own. Once an event changes the
      # process's state, the events after it are dropped.
      #
      # @return [void]
      #
      # @api private
      def run_watches
        now = Integer(Time.now)

        # Each check that's due runs in a thread of its own, so a slow one
        # doesn't hold up the others. One that isn't due would do nothing, so
        # it gets no thread.
        threads = [] #: Array[[ConditionWatch, Thread]]
        watches.each do |watch|
          threads << [watch, Thread.new { watch.run(actual_pid, now) }] if watch.due?(now)
        end
        # Most ticks have no watch due, and nothing to wait for or dispatch
        return if threads.empty?

        @transitioned = false
        dispatch_watch_events(watch_events(threads))
      end

      # Wait for the watches' threads, and return the events they fired
      #
      # Each watch that fired events is logged with them.
      #
      # @param [Array<(ConditionWatch, Thread)>] threads each watch that ran,
      #   with its thread
      #
      # @return [Array<(Symbol, String)>] each event, with the watch that
      #   fired it as the reason
      #
      # @api private
      def watch_events(threads)
        threads.each_with_object([]) do |(watch, thread), events|
          fired = thread.value #: Array[Symbol]
          next if fired.empty?

          logger.info "#{watch.name} dispatched: #{fired.join(",")}"
          fired.each do |event|
            events << [event, watch.to_s]
          end
        end
      end

      # Dispatch the watches' events, until one changes the process's state
      #
      # @param [Array<(Symbol, String)>] events each event, with its reason
      #
      # @return [void]
      #
      # @api private
      def dispatch_watch_events(events)
        events.each do |event, reason|
          break if @transitioned

          dispatch!(event, reason)
        end
      end
    end
  end
end
