lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bluepill/version'

Gem::Specification.new do |spec|
  spec.name        = 'bluepill'
  spec.version     = Bluepill::Version
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['Arya Asemanfar', 'Gary Tsang', 'Rohith Ravi']
  spec.email       = ['entombedvirus@gmail.com']
  spec.homepage    = 'http://github.com/bluepill-rb/bluepill'
  spec.summary     = 'A process monitor written in Ruby with stability and minimalism in mind.'
  spec.description = "Bluepill keeps your daemons up while taking up as little resources as possible. After all you probably want the resources of your server to be used by whatever daemons you are running rather than the thing that's supposed to make sure they are brought back up, should they die or misbehave."
  spec.license     = 'MIT'

  spec.add_dependency 'activesupport', ['>= 3.2', '< 7']
  spec.add_dependency 'blue-daemons', '~> 1.1'
  spec.add_dependency 'state_machine', '~> 1.1'
  spec.add_development_dependency 'bundler', '~> 1.3'

  spec.required_ruby_version = '>= 1.9.3'

  spec.files            = %w(CONTRIBUTING.md DESIGN.md LICENSE README.md bluepill.gemspec) + Dir['bin/*'] + Dir['lib/**/*.rb']
  spec.executables      = Dir['bin/*'].collect { |f| File.basename(f) }
  spec.require_paths    = ['lib']
end
