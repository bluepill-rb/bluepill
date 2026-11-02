# frozen_string_literal: true

describe Bluepill::ProcessFactory::Registry do
  subject(:registry) { described_class.new }

  describe "#add_process?" do
    it "adds a new process name" do
      expect(registry.add_process?("servers", "web")).to be(true)
    end

    it "refuses a name it has in the same group" do
      registry.add_process?("servers", "web")
      expect(registry.add_process?("servers", "web")).to be(false)
    end

    it "adds another name in the same group" do
      registry.add_process?("servers", "web")
      expect(registry.add_process?("servers", "worker")).to be(true)
    end

    it "adds the same name in another group" do
      registry.add_process?("a", "web")
      expect(registry.add_process?("b", "web")).to be(true)
    end

    it "treats Symbols and Strings alike" do
      registry.add_process?(:servers, :web)
      expect(registry.add_process?("servers", "web")).to be(false)
    end

    it "tells no group from a group without a name" do
      registry.add_process?(nil, "web")
      expect([registry.add_process?("", "web"), registry.add_process?(nil, "web")]).to eq([true, false])
    end

    it "keeps the group and the name apart" do
      registry.add_process?("a", "b:c")
      expect(registry.add_process?("a:b", "c")).to be(true)
    end
  end

  describe "#add_pid_file?" do
    it "adds a new pid file" do
      expect(registry.add_pid_file?("/pids/web.pid")).to be(true)
    end

    it "refuses a pid file it has" do
      registry.add_pid_file?("/pids/web.pid")
      expect(registry.add_pid_file?("/pids/web.pid")).to be(false)
    end

    it "adds another pid file" do
      registry.add_pid_file?("/pids/web.pid")
      expect(registry.add_pid_file?("/pids/worker.pid")).to be(true)
    end

    it "keeps pid files apart from process names" do
      registry.add_process?(nil, "/pids/web.pid")
      expect(registry.add_pid_file?("/pids/web.pid")).to be(true)
    end
  end
end
