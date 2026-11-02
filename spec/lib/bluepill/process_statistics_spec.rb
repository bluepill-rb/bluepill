# frozen_string_literal: true

describe Bluepill::ProcessStatistics do
  subject(:stats) { described_class.new }

  it "records events" do
    stats.record_event(:start, "some reason")
    stats.record_event(:stop, "another reason")
    expect(stats.events.size).to eq(2)
  end

  it "records #EVENTS_TO_PERSIST events" do
    (2 * Bluepill::ProcessStatistics::EVENTS_TO_PERSIST).times do
      stats.record_event(:start, "some reason")
    end
    expect(stats.events.size).to eq(Bluepill::ProcessStatistics::EVENTS_TO_PERSIST)
  end

  it "returns event history" do
    stats.record_event(:start, "some reason")
    expect(stats.to_s).to include("some reason", "event history")
  end

  it "lists the most recent event first" do
    allow(Time).to receive(:now).and_return(Time.local(2016, 1, 2, 3, 4, 5))
    stats.record_event(:start, "some reason")
    stats.record_event(:restart, nil)
    at = "at 01/02/2016 03:04:05"
    expect(stats.to_s).to eq("event history:\n  restart #{at} - unspecified\n  start #{at} - some reason")
  end
end
