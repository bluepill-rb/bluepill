require "spec_helper"

describe "Bluepill:Process" do
  it "should raise exceptions unless properly initialized" do
    lambda {
      Bluepill::Process.new
    }.should raise_error(ArgumentError)
  end
  
  it "should construct a valid object when properly initialized" do
    lambda {
      Bluepill::Process.new("test_process") do |p|
        # The absolute minimum to construct a valid process
        p.start_command = "/dev/null"
        p.pid_file = "/var/run/test_process.pid"
      end
    }.should_not raise_error
  end
  
end

describe "A Bluepill::Process object" do
  before(:each) do
    @process = Bluepill::Process.new("test_process") do |p|
      p.start_command = "hai"
      p.daemonize = true
    end
  end
  
  it "should be in the unmonitored state after construction" do
    @process.should be_unmonitored
  end  
end
