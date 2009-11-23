require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "bluepill"
    gem.summary = %Q{A process monitor written in Ruby with stability and minimalism in mind.}
    gem.description = %Q{Bluepill keeps your daemons up while taking up as little resources as possible. After all you probably want the resources of your server to be used by whatever daemons you are running rather than the thing that's supposed to make sure they are brought back up, should they die or misbehave.}
    gem.email = "entombedvirus@gmail.com"
    gem.homepage = "http://github.com/arya/bluepill"
    gem.authors = ["Arya Asemanfar", "Gary Tsang", "Rohith Ravi"]
    # gem is a Gem::Specification... see http://www.rubygems.org/read/chapter/20 for additional settings
    gem.add_dependency("daemons", ">= 1.0.9")
    gem.add_dependency("blankslate", ">= 2.1.2.2")
    gem.add_dependency("state_machine", ">= 0.8.0")
    gem.add_dependency("activesupport", ">= 2.3.4")

    gem.files -= ["bin/sample_forking_server"]
    gem.executables = ["bluepill"]
  end
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: sudo gem install jeweler"
end


require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  if File.exist?('VERSION')
    version = File.read('VERSION')
  else
    version = ""
  end

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "blue-pill #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end


namespace :version do
  task :update_file do
    version = File.read("VERSION").strip
    File.open("lib/bluepill/version.rb", "w") do |file|
      file.write <<-END
module Bluepill
  VERSION = "#{version}"
end
      END
    end
  end
end