source "https://rubygems.org"

# Specify your gem's dependencies in bluepill.gemspec
gemspec

gem "json", "< 2.3" if RUBY_VERSION < "2.0"
gem "rake"
gem "syslog" if RUBY_VERSION >= "3.4"
gem "term-ansicolor", "~> 1.3.2" if RUBY_VERSION < "2.0"
gem "tins", "~> 1.6.0" if RUBY_VERSION < "2.0"

# Duel, with its plugin that counts the objects a benchmark leaves alive,
# and StackProf for its profiles of regressions, need Ruby 3.4 or newer on
# MRI
group :development do
  if RUBY_VERSION >= "3.4" && RUBY_ENGINE == "ruby"
    gem "duel", require: false
    gem "duel-retained", require: false
    gem "stackprof", require: false
    # Duel compares with older versions of bluepill, which load these
    gem "blue-daemons", "~> 1.1", require: false
    gem "state_machine", "~> 1.1", require: false
  end
end

group :doc do
  gem "maruku", ">= 0.7"
  gem "yard", ">= 0.8"
  gem "yardstick", ">= 0.9.9", require: false if RUBY_VERSION >= "2.7"
end

group :test do
  # The specs check that configs written with ActiveSupport's durations
  # and sizes still work. ActiveSupport 5 needs Ruby 2.2.2.
  gem "activesupport", (RUBY_VERSION < "2.2.2") ? "~> 4.2" : ">= 3.2"
  gem "rspec", ">= 3"
  if RUBY_VERSION >= "2.7"
    # Standard needs RuboCop 1.91
    gem "rubocop", "~> 1.91"
    gem "rubocop-rake"
    gem "rubocop-rspec"
  end
  # Standard, and its performance rules, need Ruby 3.0 or newer
  if RUBY_VERSION >= "3.0"
    gem "standard", ">= 1.57", require: false
    gem "standard-performance", require: false
  end
  gem "simplecov", ">= 0.4"
  gem "steep", "~> 2.1", require: false if RUBY_VERSION >= "3.3" && RUBY_ENGINE == "ruby"
  # Mutant needs Ruby 3.3 or newer and doesn't support JRuby
  if RUBY_VERSION >= "3.3" && RUBY_ENGINE == "ruby"
    gem "mutant", "~> 0.17", require: false
    gem "mutant-rspec", "~> 0.17", require: false
  end
end
