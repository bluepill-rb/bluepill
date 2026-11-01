describe Bluepill::Version do
  it 'has a major version' do
    expect(Bluepill::Version.major).to be_a(Integer)
  end

  it 'has a minor version' do
    expect(Bluepill::Version.minor).to be_a(Integer)
  end

  it 'has a patch version' do
    expect(Bluepill::Version.patch).to be_a(Integer)
  end

  it 'has no pre-release version' do
    expect(Bluepill::Version.pre).to be_nil
  end

  it 'converts to a hash' do
    version = Bluepill::Version
    expect(version.to_h).to eq(major: version.major, minor: version.minor, patch: version.patch, pre: nil)
  end

  it 'converts to an array without nil parts' do
    version = Bluepill::Version
    expect(version.to_a).to eq([version.major, version.minor, version.patch])
  end

  it 'converts to a dotted string' do
    expect(Bluepill::Version.to_s).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
