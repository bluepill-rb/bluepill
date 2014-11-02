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
end

$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'bluepill'
require 'faker'
require 'rspec/core'

module Process
  def self.euid
    fail 'Process.euid should be stubbed'
  end
end
