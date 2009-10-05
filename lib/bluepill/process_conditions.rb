module Bluepill
  module ProcessConditions
    def self.name_to_class(name)
      "#{self}::#{name.to_s.camelcase}".constantize
    end
  end
end