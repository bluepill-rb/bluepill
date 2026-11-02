# frozen_string_literal: true

describe Bluepill::System::PsTable do
  subject(:table) { described_class.new(rows) }

  let(:rows) do
    {
      0 => %w[PID PPID %CPU RSS ELAPSED COMMAND],
      1 => ["1", "0", "1.5", "100", "01:00", "init"],
      2 => ["2", "1", "2.5", "200", "02:00", "child one"],
      3 => ["3", "2", "3.5", "300", "03:00", "grandchild"],
      4 => ["4", "1", "4.5", "400.5", "04:00", "child two"]
    }
  end

  it "numbers its columns in the order ps prints them" do
    columns = %i[PID PPID PCPU RSS ETIME COMMAND].collect { |name| described_class.const_get(name) }
    expect(columns).to eql [0, 1, 2, 3, 4, 5]
  end

  describe ".parse" do
    let(:output) do
      [
        "  PID  PPID  %CPU    RSS     ELAPSED ARGS",
        '  321     1  12.5  56789       01:02 ruby -e "sleep 1"',
        "  322     1   0.0      0       00:01"
      ].join("\n")
    end

    it "keys each line's fields by its pid, keeping the command whole" do
      expect(described_class.parse(output).rows).to eq(
        0 => %w[PID PPID %CPU RSS ELAPSED ARGS],
        321 => ["321", "1", "12.5", "56789", "01:02", 'ruby -e "sleep 1"'],
        322 => ["322", "1", "0.0", "0", "00:01", ""]
      )
    end

    # A pill file could set $;, which split uses when it's given no pattern
    context "when $; is set" do
      around do |example|
        separator = $;
        begin
          $; = ","
          example.run
        ensure
          $; = separator
        end
      end

      it "still splits on whitespace" do
        expect(described_class.parse(output).row(321)).to eq(["321", "1", "12.5", "56789", "01:02", 'ruby -e "sleep 1"'])
      end
    end

    it "makes a table" do
      expect(described_class.parse(output)).to be_a(described_class)
    end
  end

  describe "#rows" do
    it "is the rows it was made of" do
      expect(table.rows).to equal(rows)
    end
  end

  describe "#row" do
    it "is a process's fields" do
      expect(table.row(2)).to equal(rows.fetch(2))
    end

    it "is nil for a pid ps doesn't list" do
      expect(table.row(99)).to be_nil
    end
  end

  describe "#children" do
    it "is a process's children, in ps's order" do
      expect(table.children(1)).to eq([2, 4])
    end

    it "is NO_PIDS for a process without children" do
      expect(table.children(3)).to be(Bluepill::System::NO_PIDS)
    end

    it "builds its index of children once" do
      allow(rows).to receive(:each_pair).and_call_original
      2.times { table.children(1) }
      expect(rows).to have_received(:each_pair).once
    end
  end

  describe "#descendants" do
    it "is a process's children, followed by theirs" do
      expect(table.descendants(1)).to eq([2, 4, 3])
    end

    it "is NO_PIDS for a process without children" do
      expect(table.descendants(3)).to be(Bluepill::System::NO_PIDS)
    end

    it "leaves the index of children as it was" do
      table.descendants(1)
      expect(table.children(1)).to eq([2, 4])
    end
  end

  describe "#sum" do
    it "adds up a column of the processes' rows as Floats" do
      expect(table.sum([2, 4], described_class::RSS)).to be_a(Float).and eq(600.5)
    end

    it "skips pids ps doesn't list" do
      expect(table.sum([2, 99], described_class::PCPU)).to eq(2.5)
    end

    it "is 0.0 for no pids" do
      expect(table.sum([], described_class::RSS)).to be_a(Float).and eq(0.0)
    end

    it "adds them to a total" do
      expect(table.sum([2], described_class::PCPU, 1.5)).to eq(4.0)
    end
  end
end
