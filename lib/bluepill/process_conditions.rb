module Bluepill
  module ProcessConditions
    def self.name_to_class(name)
      "#{self}::#{name.to_s.camelcase}".constantize
    end
  end
end

require "bluepill/process_conditions/process_condition"
Dir["#{File.dirname(__FILE__)}/process_conditions/*.rb"].each do |pc|
  require pc
end

