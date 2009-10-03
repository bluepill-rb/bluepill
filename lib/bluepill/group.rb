module Bluepill
  class Group
    attr_accessor :name, :processes
    def initialize(name)
      self.name = name
      self.processes = []
    end
  end
end