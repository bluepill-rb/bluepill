$LOAD_PATH << File.expand_path('./lib', File.dirname(__FILE__))
require 'bluepill/version'

require 'bundler'
Bundler::GemHelper.install_tasks

# Only tag and push to GitHub. The push workflow (.github/workflows/push.yml)
# signs the gem and pushes it to RubyGems.
Rake::Task['release'].clear
desc "Create tag v#{Bluepill::Version} and push it to GitHub"
task 'release', [:remote] => ['build', 'release:guard_clean'] do |_, args|
  Rake::Task['release:source_control_push'].invoke(args[:remote])
end

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

task test: :spec
task default: [:spec, :rubocop]
