# -*- encoding: utf-8 -*-
module Bluepill
  module ProcessConditions
    class ZombieProcess < ProcessCondition
      def run(pid, include_children)
        System.command(pid)
      end

      def check(value)
        (value =~ /\<defunct\>/).nil?
      end
    end
  end
end