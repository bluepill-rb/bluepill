# frozen_string_literal: true

require "tmpdir"

describe Bluepill::PidFile do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "app.pid") }

  after { FileUtils.remove_entry(dir) }

  describe ".read" do
    it "is the pid in the file" do
      File.write(path, "1234\n")
      expect(described_class.read(path)).to eq(1234)
    end

    it "reads pid 1" do
      File.write(path, "1")
      expect(described_class.read(path)).to eq(1)
    end

    it "is nil without the file" do
      expect(described_class.read(path)).to be_nil
    end

    it "does not read a missing file" do
      allow(File).to receive(:read).and_call_original
      described_class.read(path)
      expect(File).not_to have_received(:read)
    end

    ["", "garbled", "0", "-5"].each do |contents|
      it "is nil for a pid file that holds #{contents.inspect}" do
        File.write(path, contents)
        expect(described_class.read(path)).to be_nil
      end
    end
  end
end
