describe Bluepill::Util do
  describe '.log_error' do
    let(:logger) { instance_double(Bluepill::Logger, err: nil) }

    it 'logs the summary, the error and each line of its backtrace' do
      error = RuntimeError.new('boom')
      error.set_backtrace(['line 1', 'line 2'])
      Bluepill::Util.log_error(logger, 'tick failed', error)
      expect(logger).to have_received(:err).with('tick failed: RuntimeError: boom').ordered
      expect(logger).to have_received(:err).with('line 1').ordered
      expect(logger).to have_received(:err).with('line 2').ordered
      expect(logger).to have_received(:err).exactly(3).times
    end

    it 'logs only the summary and the error without a backtrace' do
      Bluepill::Util.log_error(logger, 'tick failed', ArgumentError.new('bad'))
      expect(logger).to have_received(:err).with('tick failed: ArgumentError: bad').once
      expect(logger).to have_received(:err).once
    end
  end
end
