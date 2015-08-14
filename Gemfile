source 'https://rubygems.org'

# Specify your gem's dependencies in bluepill.gemspec
gemspec

if RUBY_PLATFORM =~ /jruby|java/ || RUBY_VERSION =~ /1.8|1.9.2/
  gem 'activesupport', '~> 3.0'
else
  gem 'activesupport', '~> 4.1'
end

gem 'i18n', '~> 0.6.11', :platforms => [:ruby_18]
gem 'rake'

group :doc do
  # YARD helper for ruby 1.8 (already embedded into ruby 1.9)
  gem 'ripper', :platforms => :mri_18
  gem 'maruku', '>= 0.7'
  gem 'yard', '>= 0.8'
end

group :test do
  gem 'coveralls', :require => false, :platforms => [:mri_19, :mri_20, :mri_21, :mri_22]
  gem 'faker', '>= 1.2'
  gem 'rest-client', '~> 1.6.0', :platforms => [:jruby, :ruby_18]
  gem 'rspec', '>= 3'
  gem 'rubocop', '>= 0.27', :platforms => [:ruby_19, :ruby_20, :ruby_21, :ruby_22]
  gem 'simplecov', '>= 0.4', :platforms => :ruby_19
end
