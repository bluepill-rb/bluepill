describe Bluepill::System do
  describe :pid_alive? do
    it "should be true if process responds to zero signal" do
      expect(Process).to receive(:kill).with(0, 555).and_return(0)
      expect(Bluepill::System).to be_pid_alive(555)
    end

    it "should be false if process throws exception on zero signal" do
      expect(Process).to receive(:kill).with(0, 555).and_raise(Errno::ESRCH)
      expect(Bluepill::System).not_to be_pid_alive(555)
    end
  end

  describe :store do
    it "should be Hash" do
      expect(Bluepill::System.store).to be_kind_of(Hash)
    end

    it "should return same Hash or every call" do
      expect(Bluepill::System.store).to be_equal(Bluepill::System.store)
    end

    it "should store assigned pairs" do
      Bluepill::System.store[:somekey] = 10
      expect(Bluepill::System.store[:somekey]).to be_eql(10)
    end
  end

  describe :reset_data do
    it 'should clear the #store' do
      Bluepill::System.store[:anotherkey] = Faker::Lorem.sentence
      Bluepill::System.reset_data
      expect(Bluepill::System.store).to be_empty
    end
  end

  describe :parse_etime do
    it "should parse etime format" do
      expect(Bluepill::System.parse_elapsed_time("400-00:04:01")).to be_equal(34560241)
      expect(Bluepill::System.parse_elapsed_time("02:04:02")).to be_equal(7442)
      expect(Bluepill::System.parse_elapsed_time("20:03")).to be_equal(1203)
      expect(Bluepill::System.parse_elapsed_time("invalid")).to be_equal(0)
    end
  end
end
