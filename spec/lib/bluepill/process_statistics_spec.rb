describe Bluepill::ProcessStatistics do
  before(:each) do
    @stats = described_class.new
  end

  it 'should record events' do
    @stats.record_event('some event', 'some reason')
    @stats.record_event('another event', 'another reason')
    expect(@stats.events.size).to eq(2)
  end

  it 'should record #EVENTS_TO_PERSIST events' do
    (2 * Bluepill::ProcessStatistics::EVENTS_TO_PERSIST).times do
      @stats.record_event('some event', 'some reason')
    end
    expect(@stats.events.size).to eq(Bluepill::ProcessStatistics::EVENTS_TO_PERSIST)
  end

  it 'should return event history' do
    @stats.record_event('some event', 'some reason')
    expect(@stats.to_s).to match(/some reason/)
    expect(@stats.to_s).to match(/event history/)
  end

  it 'should list the most recent event first' do
    allow(Time).to receive(:now).and_return(Time.local(2016, 1, 2, 3, 4, 5))
    @stats.record_event('first event', 'some reason')
    @stats.record_event('second event', nil)
    expect(@stats.to_s).to eq("event history:\n  second event at 01/02/2016 03:04:05 - unspecified\n  first event at 01/02/2016 03:04:05 - some reason")
  end
end
