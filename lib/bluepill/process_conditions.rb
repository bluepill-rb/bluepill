# frozen_string_literal: true

require "bluepill/check_registry"

module Bluepill
  # The checks a process can run, named in a config by their underscored
  # class name, such as `checks :mem_usage`
  #
  # CheckRegistry finds them by that name.
  #
  # @api private
  module ProcessConditions
  end
end

require "bluepill/process_conditions/process_condition"
require "bluepill/process_conditions/below_threshold"
Dir.glob("process_conditions/*.rb", base: __dir__).each { |file| require_relative file }
