# frozen_string_literal: true

describe Bluepill::Util do
  describe ".log_error" do
    let(:messages) { [] }
    let(:logger) do
      instance_double(Bluepill::Logger).tap do |logger|
        allow(logger).to receive(:err) { |message| messages << message }
      end
    end

    it "logs the summary, the error's class and message, and each backtrace line" do
      error = ArgumentError.new("bad").tap { |e| e.set_backtrace(["a.rb:1", "b.rb:2"]) }
      described_class.log_error(logger, "check failed", error)
      expect(messages).to eq(["check failed: ArgumentError: bad", "a.rb:1", "b.rb:2"])
    end

    it "logs only the summary line for an error without a backtrace" do
      described_class.log_error(logger, "check failed", RuntimeError.new("boom"))
      expect(messages).to eq(["check failed: RuntimeError: boom"])
    end
  end
end
