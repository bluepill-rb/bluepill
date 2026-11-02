# frozen_string_literal: true

# RSpec names a described module with its to_s, which is the version
describe "Bluepill::Version" do
  describe ".major" do
    it "is the major version" do
      expect(Bluepill::Version.major).to eq(0)
    end
  end

  describe ".minor" do
    it "is the minor version" do
      expect(Bluepill::Version.minor).to eq(2)
    end
  end

  describe ".patch" do
    it "is the patch version" do
      expect(Bluepill::Version.patch).to eq(7)
    end
  end

  describe ".pre" do
    it "is no pre-release version" do
      expect(Bluepill::Version.pre).to be_nil
    end
  end

  describe ".to_h" do
    it "has every part" do
      expect(Bluepill::Version.to_h).to eq(major: 0, minor: 2, patch: 7, pre: nil)
    end

    it "has the pre-release version when there is one" do
      allow(Bluepill::Version).to receive(:pre).and_return(1)
      expect(Bluepill::Version.to_h).to include(pre: 1)
    end
  end

  describe ".to_a" do
    it "has the parts without nil" do
      expect(Bluepill::Version.to_a).to eq([0, 2, 7])
    end
  end

  describe ".to_s" do
    it "is the dotted version" do
      expect(Bluepill::Version.to_s).to eq("0.2.7")
    end
  end
end
