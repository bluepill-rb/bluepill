require 'rbconfig'

# Bluepill adds the units that configs use, such as 10.seconds, to Numeric.
# That should stay the only change it makes to Ruby's own classes, since
# everything a pill file loads runs in the same process as bluepill.
describe "Loading bluepill's changes to Ruby's own classes", type: :integration do
  root = File.expand_path('..', File.dirname(__FILE__))

  # The specs have loaded bluepill already, so this runs in a Ruby of its own
  it 'only adds the units to Numeric' do
    script = File.join(root, 'spec', 'support', 'core_extensions.rb')
    ruby = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name'])
    # Only stdout, since older JRubies print JVM warnings on stderr
    output = IO.popen([ruby, script], &:read)
    expect(output).to eq("Numeric includes Bluepill::Units\n")
    expect($?).to be_success
  end
end
