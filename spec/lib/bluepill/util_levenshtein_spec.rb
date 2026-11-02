# frozen_string_literal: true

describe Bluepill::Util do
  describe ".levenshtein_distance" do
    it "counts the insertions, deletions and replacements between two strings" do
      pairs = [
        %w[start_comand start_command], %w[pid_file pidfile], %w[daemonise daemonize],
        %w[kitten sitting], %w[sitting kitten], %w[flaw lawn], %w[ab ba]
      ]
      expect(pairs.collect { |a, b| described_class.levenshtein_distance(a, b) }).to eq([1, 1, 1, 3, 3, 2, 2])
    end

    it "counts every character against an empty string" do
      pairs = [["", "uid"], ["gid", ""], ["", ""]]
      expect(pairs.collect { |a, b| described_class.levenshtein_distance(a, b) }).to eq([3, 3, 0])
    end

    it "is 0 between a string and itself" do
      expect(described_class.levenshtein_distance("stop_command", "stop_command")).to eq(0)
    end

    it "keeps its row helper private" do
      expect(described_class).not_to respond_to(:next_levenshtein_row!)
    end
  end
end
