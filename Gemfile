# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in bluepill.gemspec
gemspec

gem "rake"
gem "syslog" if RUBY_VERSION >= "3.4"

# Duel, with its plugin that counts the objects a benchmark leaves alive,
# and StackProf for its profiles of regressions, need Ruby 3.4 or newer on
# MRI
group :development do
  if RUBY_VERSION >= "3.4" && RUBY_ENGINE == "ruby"
    gem "duel", ">= 0.1.2", require: false
    gem "duel-retained", require: false
    gem "stackprof", require: false
  end
end

group :doc do
  gem "maruku", ">= 0.7"
  gem "yard", ">= 0.8"
  gem "yardstick", ">= 0.9.9", require: false
end

group :test do
  # The specs check that configs written with ActiveSupport's durations
  # and sizes still work
  gem "activesupport", ">= 3.2"
  gem "rspec", ">= 3"
  # Standard needs RuboCop 1.91
  gem "rubocop", "~> 1.91"
  gem "rubocop-rake"
  gem "rubocop-rspec"
  gem "simplecov", ">= 1"
  gem "standard", ">= 1.57", require: false
  gem "standard-performance", require: false
  gem "steep", "~> 2.1", require: false if RUBY_VERSION >= "3.3" && RUBY_ENGINE == "ruby"
  # Mutant needs Ruby 3.3 or newer and doesn't support JRuby
  if RUBY_VERSION >= "3.3" && RUBY_ENGINE == "ruby"
    gem "mutant", "~> 0.17", require: false
    gem "mutant-rspec", "~> 0.17", require: false
  end
end
