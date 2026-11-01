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

# Steep needs Ruby 3.3 or newer, so the Gemfile only installs it there
begin
  require 'steep/version'
  steep = true
rescue LoadError
  steep = false
end

if steep
  namespace :rbs do
    desc 'Install the signatures of the dependencies from rbs_collection.lock.yaml'
    task :collection do
      sh 'rbs collection install --frozen'
    end

    desc 'Validate the RBS signatures'
    task validate: :collection do
      sh 'rbs -I sig -I sig-vendor validate'
    end
  end

  desc 'Type check lib against sig with Steep'
  task steep: 'rbs:validate' do
    sh 'steep check'
  end
end

# Mutant needs Ruby 3.3 or newer, so the Gemfile only installs it there
begin
  require 'mutant/version'
  mutant = true
rescue LoadError
  mutant = false
end

if mutant
  desc 'Run mutation tests with mutant'
  task :mutant do
    sh 'mutant run'
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
default_tasks = [:spec, :rubocop]
default_tasks << :steep if steep
default_tasks << :mutant if mutant
task default: default_tasks
