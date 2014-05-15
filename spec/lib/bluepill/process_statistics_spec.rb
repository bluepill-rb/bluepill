describe Bluepill::ProcessStatistics do
  before(:each) do
    @stats = Bluepill::ProcessStatistics.new
  end

  it "should record events" do
    @stats.record_event('some event', 'some reason')
    @stats.record_event('another event', 'another reason')
    expect(@stats.events.size).to eq(2)
  end

  it "should record #EVENTS_TO_PERSIST events" do
    (2 * Bluepill::ProcessStatistics::EVENTS_TO_PERSIST).times do
      @stats.record_event('some event', 'some reason')
    end
    expect(@stats.events.size).to eq(Bluepill::ProcessStatistics::EVENTS_TO_PERSIST)
  end

  it "should return event history" do
    @stats.record_event('some event', 'some reason')
    expect(@stats.to_s).to match(/some reason/)
    expect(@stats.to_s).to match(/event history/)
  end
end
