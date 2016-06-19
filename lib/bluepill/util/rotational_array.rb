module Bluepill
  module Util
    class RotationalArray < Array
      def initialize(size)
        @capacity = size

        super() # no size - intentionally
      end

      def push(value)
        super(value)

        shift if length > @capacity
        self
      end
      alias << push
    end
  end
end
