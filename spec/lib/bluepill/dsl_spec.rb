describe Bluepill do
  describe '.application' do
    let(:app) { instance_double(Bluepill::Application, load: nil) }
    let(:options) { {foreground: true} }

    before do
      allow(Bluepill::Application).to receive(:new).with('app_name', options).and_return(app)
    end

    it 'evaluates a block without arguments in the context of the app proxy' do
      context = nil
      Bluepill.application(:app_name, options) { context = self }
      expect(context).to be_a(Bluepill::AppProxy)
      expect(app).to have_received(:load)
    end

    it 'yields the app proxy to a block with one argument' do
      yielded = nil
      Bluepill.application(:app_name, options) { |a| yielded = a }
      expect(yielded).to be_a(Bluepill::AppProxy)
      expect(yielded.app).to eq(app)
      expect(app).to have_received(:load)
    end
  end
end
