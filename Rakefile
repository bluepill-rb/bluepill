$LOAD_PATH << File.expand_path('./lib', File.dirname(__FILE__))
require 'bluepill/version'

require 'bundler'
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new

begin
  require 'rubocop/rake_task'
  RuboCop::RakeTask.new
rescue LoadError
  task :rubocop do
    $stderr.puts 'RuboCop is disabled'
  end
end

begin
  require 'yard'
  YARD::Rake::YardocTask.new do |yard|
    yard.options << "--title='bluepill #{Bluepill::Version}'"
  end
rescue LoadError
  $stderr.puts 'Please install YARD with: gem install yard'
end

task :test => :spec
task :default => [:spec, :rubocop]
