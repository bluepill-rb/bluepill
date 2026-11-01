describe Bluepill::Units do
  # The module's own method, whatever Numeric has, such as ActiveSupport's
  def units(number, method)
    described_class.instance_method(method).bind(number).call
  end

  {
    seconds: 1, second: 1, minutes: 60, minute: 60, hours: 3600, hour: 3600, days: 86_400, day: 86_400,
    kilobytes: 1024, kilobyte: 1024, megabytes: 1_048_576, megabyte: 1_048_576,
    gigabytes: 1_073_741_824, gigabyte: 1_073_741_824
  }.each do |method, factor|
    it "turns #{method} into a plain number" do
      expect(units(3, method)).to eql(3 * factor)
      expect(units(1.5, method)).to eql(1.5 * factor)
    end
  end

  it 'gives Numeric its methods' do
    expect(Numeric.ancestors).to include(described_class)
    expect(10.seconds).to eq(10)
    expect(100.megabytes).to eq(104_857_600)
  end

  it "never replaces a method Numeric's own class defines" do
    number = Class.new(Numeric) { define_method(:seconds) { :own } }.new
    expect(number.seconds).to eq(:own)
  end
end
