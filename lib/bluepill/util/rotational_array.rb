module Bluepill
  module Util
   class RotationalArray < Array
     def initialize(size)
       super
       @index = 0
     end
     
     def push(value)
       self[@index] = value
       @index = (@index + 1) % self.size
       puts @index
     end
     
     alias_method :<<, :push
     
     def pop
       raise "Cannot call pop on a rotational array"
     end

     def shift
       raise "Cannot call shift on a rotational array"
     end

     def unshift
       raise "Cannot call unshift on a rotational array"
     end
     
     def last
       self[@index - 1]
     end
   end
 end
end
