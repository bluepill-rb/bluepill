require 'simplecov'

# SimpleCov 1.x, which needs Ruby 3.2, renames add_filter and track_files
# and adds method coverage
simplecov1 = SimpleCov::VERSION.to_i >= 1

SimpleCov.start do
  if simplecov1
    skip '/spec/'
    skip '/vendor/'
    cover 'lib/**/*.rb'
  else
    add_filter '/spec/'
    add_filter '/vendor/'
    track_files 'lib/**/*.rb'
  end

  # Coverage is only enforced on MRI. JRuby counts some lines that it never
  # marks as run, such as code inside class_eval strings.
  if RUBY_ENGINE == 'ruby'
    if simplecov1
      enable_coverage :branch
      enable_coverage :method
      minimum_coverage line: 100, branch: 100, method: 100
    elsif RUBY_VERSION >= '2.5'
      # Branch coverage needs Ruby 2.5
      enable_coverage :branch
      minimum_coverage line: 100, branch: 100
    else
      minimum_coverage 100
    end
  end
end

$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

# Bundler loads the gemspec, which requires bluepill/version, before
# SimpleCov starts. Load it again so its coverage is recorded.
load File.expand_path('../lib/bluepill/version.rb', File.dirname(__FILE__))

require 'bluepill'
require 'rspec/core'

# Specs must stub Process.euid before bluepill code uses it. Other callers,
# such as FileUtils.remove_entry_secure on Ruby 1.9, get the real value.
module Process
  LIB_DIR = File.expand_path('../lib', File.dirname(__FILE__))

  class << self
    alias unstubbed_euid euid

    def euid
      raise 'Process.euid should be stubbed' if caller.first.start_with?(LIB_DIR)

      unstubbed_euid
    end
  end
end
