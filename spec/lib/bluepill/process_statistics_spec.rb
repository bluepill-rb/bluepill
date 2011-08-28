describe Bluepill::ProcessStatistics do
  before(:each) do
    @stats = Bluepill::ProcessStatistics.new
  end

  it "should record events" do
    @stats.record_event('some event', 'some reason')
    @stats.record_event('another event', 'another reason')
    @stats.events.should have(2).events
  end

  it "should record #EVENTS_TO_PERSIST events" do
    (2 * Bluepill::ProcessStatistics::EVENTS_TO_PERSIST).times do
      @stats.record_event('some event', 'some reason')
    end
    @stats.events.should have(Bluepill::ProcessStatistics::EVENTS_TO_PERSIST).events
  end

  it "should return event history" do
    @stats.record_event('some event', 'some reason')
    @stats.to_s.should match(/some reason/)
    @stats.to_s.should match(/event history/)
  end
end