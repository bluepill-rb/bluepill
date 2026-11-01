require 'simplecov'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  minimum_coverage(41)
end

$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'bluepill'
require 'faker'
require 'rspec/core'

module Process
  def self.euid
    raise 'Process.euid should be stubbed'
  end
end
