describe Bluepill::System do
  describe :pid_alive? do
    it "should be true if process responds to zero signal" do
      Process.should_receive(:kill).with(0, 555).and_return(0)
      Bluepill::System.should be_pid_alive(555)
    end

    it "should be false if process throws exception on zero signal" do
      Process.should_receive(:kill).with(0, 555).and_raise(Errno::ESRCH)
      Bluepill::System.should_not be_pid_alive(555)
    end
  end

  describe :store do
    it "should be Hash" do
      Bluepill::System.store.should be_kind_of(Hash)
    end

    it "should return same Hash or every call" do
      Bluepill::System.store.should be_equal(Bluepill::System.store)
    end

    it "should store assigned pairs" do
      Bluepill::System.store[:somekey] = 10
      Bluepill::System.store[:somekey].should be_eql(10)
    end
  end

  describe :reset_data do
    it 'should clear the #store' do
      Bluepill::System.store[:anotherkey] = Faker::Lorem.sentence
      Bluepill::System.reset_data
      Bluepill::System.store.should be_empty
    end
  end

  describe :parse_etime do
    it "should parse etime format" do
      Bluepill::System.parse_elapsed_time("400-00:04:01").should be_equal(34560241)
      Bluepill::System.parse_elapsed_time("02:04:02").should be_equal(7442)
      Bluepill::System.parse_elapsed_time("20:03").should be_equal(1203)
      Bluepill::System.parse_elapsed_time("invalid").should be_equal(0)
    end
  end
end
