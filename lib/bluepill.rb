# frozen_string_literal: true

require "rubygems"

# A process monitor that keeps daemons running
#
# A config file calls {Bluepill.application} to describe an application's
# processes, and the bluepill daemon monitors and restarts them.
#
# @api public
module Bluepill
  # Set up Bundler when bluepill runs with a Gemfile
  #
  # Bluepill calls this once, when it's loaded, so that it runs with the
  # app's bundle, such as under bundle exec.
  #
  # @param [String, nil] gemfile the path of the Gemfile, BUNDLE_GEMFILE by
  #   default
  #
  # @return [Boolean, nil] what requiring bundler/setup returned, or nil
  #   when there's no Gemfile
  #
  # @api private
  def self.setup_bundler(gemfile = ENV.fetch("BUNDLE_GEMFILE", nil))
    require "bundler/setup" if gemfile && File.exist?(gemfile)
  end
end

Bluepill.setup_bundler

require "monitor"
require "timeout"
require "logger"

require "bluepill/clock"
require "bluepill/deprecation"
require "bluepill/units"
require "bluepill/util/inflections"

require "bluepill/dsl/process_proxy"
require "bluepill/dsl/process_factory"
require "bluepill/dsl/app_proxy"

require "bluepill/application"
require "bluepill/controller"
require "bluepill/socket"
require "bluepill/process"
require "bluepill/process_statistics"
require "bluepill/group"
require "bluepill/logger"
require "bluepill/condition_watch"
require "bluepill/trigger"
require "bluepill/triggers/flapping"
require "bluepill/dsl"
require "bluepill/system"

require "bluepill/process_conditions"

require "bluepill/util/rotational_array"

require "bluepill/version"
