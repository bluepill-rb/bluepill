module Bluepill
  module ProcessConditions
    # Process must have cache_actual_pid set to false to function correctly:
    #
    # process.checks :zombie_process, :every => 5.seconds
    # process.cache_actual_pid = false

    class ZombieProcess < ProcessCondition
      def run(pid, _include_children)
        System.command(pid)
      end

      def check(value)
        (value =~ /\<defunct\>/).nil?
      end
    end
  end
end
