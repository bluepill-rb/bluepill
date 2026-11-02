# frozen_string_literal: true

module Bluepill
  # The checks a process can run, named in a config by their underscored
  # class name, such as `checks :mem_usage`
  #
  # @api private
  module ProcessConditions
    # Return the check class a config names
    #
    # @param [Symbol, String] name the check's underscored name, such as
    #   :mem_usage
    #
    # @return [Class] the ProcessCondition subclass, such as MemUsage
    #
    # @raise [NameError] when no check has that name
    #
    # @api private
    def self.[](name) = const_get(Util.camelize(name))
  end
end

require "bluepill/process_conditions/process_condition"
require "bluepill/process_conditions/below_threshold"
Dir["#{File.dirname(__FILE__)}/process_conditions/*.rb"].each do |pc|
  require pc
end
