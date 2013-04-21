describe Bluepill::Process do
  before(:all) do
    Bluepill::ProcessJournal.base_dir = './.bluepill'
    Bluepill::ProcessJournal.logger = Bluepill::Logger.new(:log_file => 'bluepill.log', :stdout => false).prefix_with('rspec')
  end

  subject do
    Bluepill::Process.new(:proc_name, [],
      :logger => Bluepill::Logger.new,
    )
  end

  describe "#initialize" do
    context "defaults" do
      [
        :start_command, :stop_command, :restart_command, :stdout, :stderr, :stdin,
        :daemonize, :pid_file, :working_dir, :uid, :gid, :child_process_factory,
        :pid_command, :auto_start, :supplementary_groups, :stop_signals
      ].each do |attr|
        its(attr) { should be_nil }
      end
      its(:monitor_children) { should be_false }
      its(:cache_actual_pid) { should be_true }
      its(:start_grace_time) { should eq 3 }
      its(:stop_grace_time) { should eq 3 }
      its(:restart_grace_time) { should eq 3 }
      its(:on_start_timeout) { should eq "start" }
      its(:environment) { should eq Hash[] }
    end

    context "overrides" do
      subject { Bluepill::Process.new(:proc_name, [], :start_grace_time => 17) }
      its(:start_grace_time) { should eq 17 }
    end
  end

  describe "#start_process" do
    it "functions" do
      subject.stub(:start_command) { "/etc/init.d/script start" }
      subject.stub(:on_start_timeout) { "freakout" }
      subject.logger.stub(:warning)
      subject.stub(:daemonize?) { false }

      subject.should_receive(:with_timeout)
        .with(3, "freakout")
        .and_yield

      Bluepill::System.should_receive(:execute_blocking)
        .with("/etc/init.d/script start", subject.system_command_options)
        .and_return(exit_code: 0)

      subject.start_process
    end

    describe "#stop_process" do
      it "functions" do
        subject.stub(:stop_command) { "/etc/init.d/script stop" }
        subject.logger.stub(:warning)
        subject.should_receive(:with_timeout)
          .with(3, "stop")
          .and_yield

        Bluepill::System.should_receive(:execute_blocking)
          .with("/etc/init.d/script stop", subject.system_command_options)
          .and_return(exit_code: 0)

        subject.stop_process
      end
    end

    describe "#restart_process" do
      it "functions" do
        subject.stub(:restart_command) { "/etc/init.d/script restart" }
        subject.logger.stub(:warning)
        subject.should_receive(:with_timeout)
          .with(3, "restart")
          .and_yield

        Bluepill::System.should_receive(:execute_blocking)
          .with("/etc/init.d/script restart", subject.system_command_options)
          .and_return(exit_code: 0)

        subject.restart_process
      end
    end
  end

  describe "#with_timeout" do
    let(:block) { proc { nil } }

    before(:each) do
      subject.logger.stub(:err)
      Timeout.should_receive(:timeout).with(3.to_f, &block).and_raise(Timeout::Error)
    end

    it "proceeds to next_state on timeout." do
      subject.should_receive(:dispatch!).with("state_override")
      subject.with_timeout(3, "state_override", &block)
    end
  end

end
