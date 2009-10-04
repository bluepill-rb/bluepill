require "rubygems"

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'bluepill'
require 'spec'
require 'spec/autorun'
require "ruby-debug"

Spec::Runner.configure do |config|
  
end
