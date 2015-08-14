lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bluepill/version'

Gem::Specification.new do |s|
  s.name        = 'bluepill'
  s.version     = Bluepill::VERSION.dup
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Arya Asemanfar', 'Gary Tsang', 'Rohith Ravi']
  s.email       = ['entombedvirus@gmail.com']
  s.homepage    = 'http://github.com/bluepill-rb/bluepill'
  s.summary     = 'A process monitor written in Ruby with stability and minimalism in mind.'
  s.description = "Bluepill keeps your daemons up while taking up as little resources as possible. After all you probably want the resources of your server to be used by whatever daemons you are running rather than the thing that's supposed to make sure they are brought back up, should they die or misbehave."
  s.license     = 'MIT'

  s.add_dependency 'activesupport', ['>= 3.2', '< 5']
  s.add_dependency 'blue-daemons', '~> 1.1'
  s.add_dependency 'state_machine', '~> 1.1'
  s.add_development_dependency 'bundler', '~> 1.3'

  s.files            = %w(CONTRIBUTING.md DESIGN.md LICENSE README.md bluepill.gemspec) + Dir['bin/*'] + Dir['lib/**/*.rb']
  s.executables      = Dir['bin/*'].collect { |f| File.basename(f) }
  s.require_paths    = ['lib']
end
