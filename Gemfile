source 'https://rubygems.org'

# Specify your gem's dependencies in bluepill.gemspec
gemspec

gem 'activesupport', '~> 4.2' if RUBY_VERSION < '2.2.2'
gem 'json', '< 2.3' if RUBY_VERSION < '2.0'
gem 'rake'
gem 'syslog' if RUBY_VERSION >= '3.4'
gem 'term-ansicolor', '~> 1.3.2' if RUBY_VERSION < '2.0'
gem 'tins', '~> 1.6.0' if RUBY_VERSION < '2.0'

group :doc do
  gem 'maruku', '>= 0.7'
  gem 'yard', '>= 0.8'
end

group :test do
  gem 'rspec', '>= 3'
  gem 'rubocop', '~> 1.92' if RUBY_VERSION >= '2.7'
  gem 'simplecov', '>= 0.4'
end
