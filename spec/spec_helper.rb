require 'simplecov'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  track_files 'lib/**/*.rb'

  if RUBY_ENGINE == 'ruby' && RUBY_VERSION >= '3.2'
    # SimpleCov 1.x, which needs Ruby 3.2, adds method coverage
    enable_coverage :branch
    enable_coverage :method
    minimum_coverage line: 100, branch: 100, method: 100
  elsif RUBY_ENGINE == 'ruby' && RUBY_VERSION >= '2.5'
    # Branch coverage needs Ruby 2.5
    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
  else
    minimum_coverage 100
  end
end

$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'bluepill'
require 'rspec/core'

module Process
  def self.euid
    raise 'Process.euid should be stubbed'
  end
end
