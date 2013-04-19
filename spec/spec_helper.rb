if RUBY_VERSION >= '1.9'
  if ENV['ENABLE_SIMPLECOV']
    require 'simplecov'
    SimpleCov.start
  end
else
  require 'rubygems'
end

require 'faker'
require 'rspec/core'

$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'bluepill'
