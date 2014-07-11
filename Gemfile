source 'https://rubygems.org'

# Specify your gem's dependencies in bluepill.gemspec
gemspec

if RUBY_PLATFORM =~ /jruby|java/ || RUBY_VERSION =~ /1.8|1.9.2/
  gem 'activesupport', '~> 3.0'
else
  gem 'activesupport', '~> 4.1'
end

gem 'rake'

group :doc do
  # YARD helper for ruby 1.8 (already embedded into ruby 1.9)
  gem 'ripper', :platforms => :mri_18
  gem 'maruku', '>= 0.7'
  gem 'yard', '>= 0.8'
end

group :test do
  gem 'coveralls', :require => false, :platforms => [:mri_19, :mri_20, :mri_21]
  gem 'faker', '>= 1.2'
  gem 'rest-client', '~> 1.6.0', :platforms => [:jruby, :ruby_18]
  gem 'rspec', '>= 3'
  gem 'simplecov', '>= 0.4', :platforms => :ruby_19
end
