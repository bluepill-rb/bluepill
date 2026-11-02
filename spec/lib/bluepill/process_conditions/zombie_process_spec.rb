describe Bluepill::ProcessConditions::ZombieProcess do
  subject(:condition) { described_class.new }

  it "returns the command of the process" do
    allow(Bluepill::System).to receive(:command).with(123).and_return("ruby server.rb")
    expect(condition.run(123, false)).to eq("ruby server.rb")
  end

  it "passes when the process is not defunct" do
    expect(condition.check?("ruby server.rb")).to be true
  end

  it "fails when the process is defunct" do
    expect(condition.check?("[ruby] <defunct>")).to be false
  end
end
