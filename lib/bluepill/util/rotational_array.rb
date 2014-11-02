module Bluepill
  module Util
    class RotationalArray < Array
      def initialize(size)
        @capacity = size

        super() # no size - intentionally
      end

      def push(value)
        super(value)

        self.shift if self.length > @capacity
        self
      end
      alias_method :<<, :push
    end
  end
end
