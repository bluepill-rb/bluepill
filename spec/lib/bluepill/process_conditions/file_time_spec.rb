# frozen_string_literal: true

require "fileutils"
require "tmpdir"

describe Bluepill::ProcessConditions::FileTime do
  subject(:condition) { described_class.new(below: 60, filename: filename) }

  let(:dir) { Dir.mktmpdir }
  let(:filename) { File.join(dir, "heartbeat") }

  after { FileUtils.remove_entry(dir) }

  describe "#initialize" do
    it "can be created without options" do
      expect(described_class.new).to be_a(described_class)
    end

    it "stores its options" do
      expect(condition.instance_variable_get(:@options)).to eq(below: 60, filename: filename)
    end

    it "checks against the given limit" do
      expect([condition.check?(59), condition.check?(60)]).to eq([true, false])
    end

    it "watches the given file" do
      File.write(filename, "")
      expect(condition.run(123, false)).to be_a(Float)
    end
  end

  describe "#run" do
    it "returns the time since the file was modified" do
      File.write(filename, "")
      mtime = File.mtime(filename)
      allow(Time).to receive(:now).and_return(mtime + 30)
      expect(condition.run(123, false)).to eq(30)
    end

    it "returns nil when the file does not exist" do
      expect(condition.run(123, false)).to be_nil
    end

    it "returns the error when the file cannot be read" do
      error = Errno::EACCES.new(filename)
      allow(File).to receive(:exist?).with(filename).and_return(true)
      allow(File).to receive(:mtime).with(filename).and_raise(error)
      expect(condition.run(123, false)).to eq(error)
    end
  end

  describe "#check?" do
    it "fails when there is no value" do
      expect(condition.check?(nil)).to be false
    end

    it "fails when the file could not be read" do
      expect(condition.check?(Errno::EACCES.new(filename))).to be false
    end

    it "passes when the file was modified recently" do
      expect(condition.check?(59)).to be true
    end

    it "fails when the file was not modified recently" do
      expect(condition.check?(60)).to be false
    end
  end
end
