# frozen_string_literal: true

describe Bluepill::System::CommandResult do
  describe ".from_h" do
    it "reads what the command's child reports" do
      result = described_class.from_h(stdout: "out", stderr: "err", exit_code: 2)
      expect([result.exit_code, result.stdout, result.stderr]).to eq [2, "out", "err"]
    end

    it "needs every field" do
      expect { described_class.from_h(exit_code: 0, stdout: "") }.to raise_error(KeyError)
    end
  end

  describe "#to_h" do
    it "has the exit code and the output" do
      result = described_class.new(exit_code: 1, stdout: "out", stderr: "err")
      expect(result.to_h).to eq(exit_code: 1, stdout: "out", stderr: "err")
    end

    it "has empty output by default" do
      expect(described_class.new(exit_code: 0).to_h).to eq(exit_code: 0, stdout: "", stderr: "")
    end
  end

  describe "#success?" do
    it "is true for exit code 0" do
      expect(described_class.new(exit_code: 0).success?).to be true
    end

    it "is false for another exit code" do
      expect([1, -1].collect { |code| described_class.new(exit_code: code).success? }).to eq [false, false]
    end

    it "is false when a signal ended the command" do
      expect(described_class.new(exit_code: nil).success?).to be false
    end
  end
end
