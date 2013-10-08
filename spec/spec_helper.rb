if RUBY_VERSION >= '1.9'
  if ENV['ENABLE_SIMPLECOV']
    require 'simplecov'
    SimpleCov.start
  end
  begin
    require 'coveralls'
    Coveralls.wear!
  rescue LoadError
  end
else
  require 'rubygems'
end

require 'faker'
require 'rspec/core'

$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

module Process
  def self.euid
    raise "Process.euid should be stubbed"
  end
end

require 'bluepill'
