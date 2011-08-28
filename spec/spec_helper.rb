if RUBY_VERSION >= '1.9' && ENV['ENABLE_SIMPLECOV']
  require 'simplecov'
  SimpleCov.start
else
  require 'rubygems'
end

require 'faker'
require 'rspec/core'


$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

RSpec.configure do |conf|
  conf.mock_with :rr
end

require 'bluepill'
