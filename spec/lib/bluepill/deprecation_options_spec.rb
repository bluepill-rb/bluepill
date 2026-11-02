# frozen_string_literal: true

describe Bluepill::Deprecation do
  let(:watch_keys) { Bluepill::ConditionWatch::WATCH_KEYS }

  describe ".check_options" do
    it "warns about an option that 0.3.0 rejects" do
      expect { described_class.check_options(:mem_usage, {below: 1, evry: 10}, watch_keys) }.to output(
        "DEPRECATION: bluepill 0.3.0 rejects the option evry: of checks :mem_usage, which 0.2 ignores. Remove it, or fix its name.\n"
      ).to_stderr
    end

    it "warns about an option meant for another check" do
      expect { described_class.check_options(:http, {url: "http://localhost/", within: 5}, watch_keys) }.to output(/option within: of checks :http/).to_stderr
    end

    it "takes the check's name as a String" do
      expect { described_class.check_options("http", {url: "http://localhost/", within: 5}, watch_keys) }.to output(/of checks :http,/).to_stderr
    end

    it "says nothing about the options that the watch and the check take" do
      options = {logger: nil, fires: :stop, every: 10, times: [3, 5], include_children: true, filename: "/tmp/a", below: 5}
      expect { described_class.check_options(:file_time, options, watch_keys) }.not_to output.to_stderr
    end

    it "says nothing about every option of an http check" do
      options = {url: "http://localhost/", kind: :ok, pattern: /ok/, timeout: 1, open_timeout: 1, read_timeout: 1, verify_ssl: true}
      expect { described_class.check_options(:http, options, watch_keys) }.not_to output.to_stderr
    end

    it "warns about the watch's options on a trigger" do
      expect { described_class.check_options(:flapping, {every: 10, times: 2}, described_class::NO_OPTIONS) }.to output(
        /option every: of checks :flapping/
      ).to_stderr
    end

    it "says nothing about a trigger's own options" do
      options = {times: 2, within: 30, retry_in: 7}
      expect { described_class.check_options(:flapping, options, described_class::NO_OPTIONS) }.not_to output.to_stderr
    end

    it "says nothing about a custom check's options" do
      expect { described_class.check_options(:log_size, {path: "/tmp/a"}, watch_keys) }.not_to output.to_stderr
    end

    it "warns about an option that a check needs" do
      expect { described_class.check_options(:mem_usage, {every: 10}, watch_keys) }.to output(
        "DEPRECATION: bluepill 0.3.0 fails the config when checks :mem_usage has no below: option, " \
        "which it needs to check anything in 0.2 too. Add it.\n"
      ).to_stderr
    end

    it "warns about each option that a check needs" do
      expect { described_class.check_options(:file_time, {}, watch_keys) }.to output(/no filename: option.*\n.*no below: option/).to_stderr
    end

    it "says nothing about a check that needs no options" do
      expect { described_class.check_options(:zombie_process, {}, watch_keys) }.not_to output.to_stderr
    end
  end

  describe ".check_watch" do
    it "warns about the watch's options" do
      expect { described_class.check_watch(:mem_usage, {below: 1, evry: 5}, []) }.to output(/option evry: of checks :mem_usage/).to_stderr
    end

    it "warns about the watch's events" do
      expect { described_class.check_watch(:mem_usage, {below: 1}, ["stop"]) }.to output(/fires: "stop" of checks :mem_usage/).to_stderr
    end
  end

  describe ".check_fires" do
    it "warns about an event that 0.3.0 rejects" do
      expect { described_class.check_fires(:mem_usage, ["stop", :clean_threads]) }.to output(
        "DEPRECATION: bluepill 0.3.0 takes fires: only as :start, :stop, :unmonitor or :restart, " \
        "so fires: \"stop\", :clean_threads of checks :mem_usage fails the config. Use the Symbols, such as fires: :stop.\n"
      ).to_stderr
    end

    it "says nothing about the events that 0.3.0 takes" do
      expect { described_class.check_fires(:mem_usage, %i[start stop unmonitor restart]) }.not_to output.to_stderr
    end
  end

  describe ".check_on_start_timeout" do
    it "warns about a String" do
      expect { described_class.check_on_start_timeout("web", on_start_timeout: "unmonitor") }.to output(
        "DEPRECATION: bluepill 0.3.0 takes on_start_timeout only as :start, :stop, :unmonitor or :restart, " \
        "so process 'web''s on_start_timeout of \"unmonitor\" fails the config. Use the Symbols, such as on_start_timeout = :unmonitor.\n"
      ).to_stderr
    end

    it "warns about an event that 0.3.0 rejects" do
      expect { described_class.check_on_start_timeout("web", on_start_timeout: :clean_threads) }.to output(/of :clean_threads/).to_stderr
    end

    it "says nothing about the events that 0.3.0 takes" do
      expect { described_class::EVENTS.each { |event| described_class.check_on_start_timeout("web", on_start_timeout: event) } }.not_to output.to_stderr
    end

    it "says nothing about a process that doesn't set it" do
      expect { described_class.check_on_start_timeout("web", {}) }.not_to output.to_stderr
    end
  end
end
