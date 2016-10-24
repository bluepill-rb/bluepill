source 'https://rubygems.org'

# Specify your gem's dependencies in bluepill.gemspec
gemspec

gem 'activesupport', '~> 4.2' if RUBY_VERSION < '2.2.2'
gem 'tins', '~> 1.6.0' if RUBY_VERSION < '2.0'
gem 'term-ansicolor', '~> 1.3.2' if RUBY_VERSION < '2.0'
gem 'rake'

group :doc do
  gem 'maruku', '>= 0.7'
  gem 'yard', '>= 0.8'
end

group :test do
  gem 'coveralls', require: false
  gem 'faker', '>= 1.2'
  gem 'rspec', '>= 3'
  gem 'rubocop', '>= 0.33'
  gem 'simplecov', '>= 0.4'
end
