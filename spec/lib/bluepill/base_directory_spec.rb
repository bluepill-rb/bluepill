# frozen_string_literal: true

require "tmpdir"

describe Bluepill::BaseDirectory do
  subject(:base_directory) { described_class.new("/var/run/bluepill") }

  it "keeps its path" do
    expect(base_directory.path).to eq("/var/run/bluepill")
  end

  it "has the sockets in socks" do
    expect(base_directory.sockets_dir).to eq("/var/run/bluepill/socks")
  end

  it "has the pid files in pids" do
    expect(base_directory.pids_dir).to eq("/var/run/bluepill/pids")
  end

  it "names an application's socket after it" do
    expect(base_directory.socket_file("app")).to eq("/var/run/bluepill/socks/app.sock")
  end

  it "names an application's pid file after it" do
    expect(base_directory.pid_file("app")).to eq("/var/run/bluepill/pids/app.pid")
  end

  it "keeps an application's processes' pid files in a directory named after it" do
    expect(base_directory.process_pids_dir("app")).to eq("/var/run/bluepill/pids/app")
  end

  describe "#socket_names" do
    let(:dir) { Dir.mktmpdir }
    let(:base_directory) { described_class.new(dir) }

    after { FileUtils.remove_entry(dir) }

    it "is the names of the applications with a socket" do
      FileUtils.mkdir_p(File.join(dir, "socks"))
      %w[a.sock b.sock other.txt].each { |file| FileUtils.touch(File.join(dir, "socks", file)) }
      FileUtils.touch(File.join(dir, "c.sock"))
      expect(base_directory.socket_names).to contain_exactly("a", "b")
    end

    it "is empty without a sockets directory" do
      expect(base_directory.socket_names).to eq([])
    end
  end
end
