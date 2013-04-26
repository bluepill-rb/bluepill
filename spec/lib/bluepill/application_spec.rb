describe Bluepill::Application do
  describe "#initialize" do
    let(:options){ {} }
    subject {described_class.new('test', options)}
    before(:each) {described_class.any_instance.should_receive(:setup_pids_dir)}
    
    context "when euid is not root" do
      before(:each) {::Process.stub(:euid).and_return(1)}
      its(:base_dir){ should eq(File.join(ENV['HOME'], '.bluepill')) }
    end
    context "when euid is root" do
      before(:each) {::Process.stub(:euid).and_return(0)}
      its(:base_dir) { should eq('/var/run/bluepill') }
    end
    
    context "when option base_dir is specified" do
      let(:options) { {:base_dir=>'/var/bluepill'} }
      its(:base_dir) { should eq(options[:base_dir]) }
    end

    context "when environment BLUEPILL_BASE_DIR is specified" do
      before(:each) {ENV['BLUEPILL_BASE_DIR'] = '/bluepill'}
      its(:base_dir) { should eq(ENV['BLUEPILL_BASE_DIR']) }

      context "and option base_dir is specified" do
        let(:options) { {:base_dir=>'/var/bluepill'} }
        its(:base_dir) { should eq(options[:base_dir]) }
      end
    end
  end
end