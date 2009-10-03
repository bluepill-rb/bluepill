module Bluepill
  module ProcessConditions
    def self.name_to_class(name)
      "#{self}::#{name}".constantize
    end
  end
end