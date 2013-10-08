source 'https://rubygems.org'

# Specify your gem's dependencies in bluepill.gemspec
gemspec

gem 'activesupport', '~> 3.0', :platforms => [:ruby_18, :jruby]
gem 'rake'

group :doc do
  # YARD helper for ruby 1.8 (already embedded into ruby 1.9)
  gem 'ripper', :platforms => :mri_18
  gem 'maruku', '>= 0.7'
  gem 'yard', '>= 0.8'
end

group :test do
  gem 'faker', '>= 1.2'
  gem 'rspec', '>= 2.14'
  gem 'simplecov', '>= 0.4', :platforms => :ruby_19
end

gem "coveralls", :require => false, :platforms => [:mri_19, :mri_20], :group => :development
