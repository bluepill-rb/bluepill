describe Bluepill::System do
  describe :pid_alive? do
    it "should be true if process responds to zero signal" do
      mock(::Process).kill(0, 555)
      Bluepill::System.should be_pid_alive(555)
    end

    it "should be false if process throws exception on zero signal" do
      mock(::Process).kill(0, 555) { raise Errno::ESRCH.new  }
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
end