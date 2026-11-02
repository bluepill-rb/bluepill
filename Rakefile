# frozen_string_literal: true

$LOAD_PATH << File.expand_path("lib", __dir__)
require "bluepill/version"

require "bundler"
Bundler::GemHelper.install_tasks

# Only tag and push to GitHub. The push workflow (.github/workflows/push.yml)
# signs the gem and pushes it to RubyGems.
Rake::Task["release"].clear
desc "Create tag v#{Bluepill::Version} and push it to GitHub"
task "release", [:remote] => ["build", "release:guard_clean"] do |_, args|
  Rake::Task["release:source_control_push"].invoke(args[:remote])
end

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new

require "rubocop/rake_task"
RuboCop::RakeTask.new

# Steep needs Ruby 3.3 or newer, so the Gemfile only installs it there
begin
  require "steep/version"
  steep = true
rescue LoadError
  steep = false
end

if steep
  namespace :rbs do
    desc "Install the signatures of the dependencies from rbs_collection.lock.yaml"
    task :collection do
      sh "rbs collection install --frozen"
    end

    desc "Validate the RBS signatures"
    task validate: :collection do
      sh "rbs -I sig -I sig-vendor validate"
    end
  end

  desc "Type check lib against sig with Steep"
  task steep: "rbs:validate" do
    sh "steep check"
  end
end

# Mutant needs Ruby 3.3 or newer, so the Gemfile only installs it there
begin
  require "mutant/version"
  mutant = true
rescue LoadError
  mutant = false
end

if mutant
  desc "Run mutation tests with mutant (CI splits it into shards)"
  task :mutant do
    sh "mutant run"
  end

  namespace :mutant do
    desc "List the subjects touched since REF (every one, without a REF), one per line"
    task :subjects, [:ref] do |_task, args|
      require_relative "tasks/mutant_shard"
      puts MutantShard.subjects(args[:ref])
    end

    desc "Run mutant on shard INDEX of TOTAL of the subjects touched since REF (every one, without a REF)"
    task :shard, [:ref, :index, :total] do |_task, args|
      require "shellwords"
      require_relative "tasks/mutant_shard"
      index = Integer(args.fetch(:index))
      total = Integer(args.fetch(:total))
      subjects = MutantShard.subjects(args[:ref])
      mine = MutantShard.shard(subjects, index, total)

      if mine.empty?
        puts "Shard #{index} of #{total}: no subjects"
      else
        puts "Shard #{index} of #{total}: #{mine.size} of #{subjects.size} subjects"
        sh "mutant run #{mine.collect { |subject| Shellwords.escape(subject) }.join(" ")}"
      end
    end
  end
end

begin
  require "yard"
  YARD::Rake::YardocTask.new do |yard|
    yard.options << "--title='bluepill #{Bluepill::Version}'"
  end
rescue LoadError
  $stderr.puts "Please install YARD with: gem install yard"
end

require "yardstick/rake/measurement"
require "yardstick/rake/verify"

Yardstick::Rake::Measurement.new(:yardstick_measure)

# Fails unless every method in lib is documented
Yardstick::Rake::Verify.new(:yardstick) do |verify|
  verify.threshold = 100
end

desc "Run the specs, like rake spec"
task test: :spec
# Standard needs Ruby 3.0 or newer, so the Gemfile only installs it there.
# Its rake standard task checks the code against Standard's style.
begin
  require "standard/rake"
  standard = true
rescue LoadError
  standard = false
end

default_tasks = %i[spec rubocop]
default_tasks << :standard if standard
default_tasks << :yardstick
default_tasks << :steep if steep
default_tasks << :mutant if mutant
task default: default_tasks

# Duel needs Ruby 3.4 or newer, so the Gemfile only installs it there
begin
  require "duel/rake_task"
  Duel::RakeTask.new
rescue LoadError
  nil
end
