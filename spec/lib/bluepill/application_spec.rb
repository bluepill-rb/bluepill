describe Bluepill::Application do
  describe '#initialize' do
    let(:options) { {} }
    subject { described_class.new('test', options) }
    before(:each) { expect_any_instance_of(described_class).to receive(:setup_pids_dir) }

    context 'when euid is not root' do
      before(:each) { allow(::Process).to receive(:euid).and_return(1) }

      describe '#base_dir' do
        subject { super().base_dir }
        it { should eq(File.join(ENV['HOME'], '.bluepill')) }
      end
    end
    context 'when euid is root' do
      before(:each) { allow(::Process).to receive(:euid).and_return(0) }

      describe '#base_dir' do
        subject { super().base_dir }
        it { should eq('/var/run/bluepill') }
      end
    end

    context 'when option base_dir is specified' do
      let(:options) { {base_dir: '/var/bluepill'} }

      describe '#base_dir' do
        subject { super().base_dir }
        it { should eq(options[:base_dir]) }
      end
    end

    context 'when environment BLUEPILL_BASE_DIR is specified' do
      before(:each) { ENV['BLUEPILL_BASE_DIR'] = '/bluepill' }

      describe '#base_dir' do
        subject { super().base_dir }
        it { should eq(ENV['BLUEPILL_BASE_DIR']) }
      end

      context 'and option base_dir is specified' do
        let(:options) { {base_dir: '/var/bluepill'} }

        describe '#base_dir' do
          subject { super().base_dir }
          it { should eq(options[:base_dir]) }
        end
      end
    end
  end
end
