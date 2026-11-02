describe Bluepill::ProcessFactory do
  around do |example|
    process_keys = Bluepill::ProcessFactory.class_variable_get(:@@process_keys)
    pid_files = Bluepill::ProcessFactory.class_variable_get(:@@pid_files)
    Bluepill::ProcessFactory.class_variable_set(:@@process_keys, {})
    Bluepill::ProcessFactory.class_variable_set(:@@pid_files, {})
    begin
      example.run
    ensure
      Bluepill::ProcessFactory.class_variable_set(:@@process_keys, process_keys)
      Bluepill::ProcessFactory.class_variable_set(:@@pid_files, pid_files)
    end
  end

  # Silence the warning for processes without a known pid. The output
  # matcher swaps $stderr, so specs can still check what is written.
  before { allow($stderr).to receive(:puts) }

  def create(name, block, attributes = {})
    Bluepill::ProcessFactory.new(attributes, block).create_process(name, '/pids')
  end

  def expect_config_error(message, &block)
    expect do
      expect(&block).to raise_error(SystemExit) { |e| expect(e.status).to eq(6) }
    end.to output(message).to_stderr
  end

  describe '#create_process' do
    context 'with what bluepill 0.2.0 changes' do
      let(:pre_start_warning) do
        'DEPRECATION: bluepill 0.2.0 kills a pre_start_command that runs longer than hook_timeout, 30 seconds by default, ' \
          "and starts the process even when the command can't run, where 0.1 waits for it however long it takes. " \
          "Set hook_timeout, which 0.1 ignores, if it can take longer.\n"
      end

      it 'warns once that 0.2.0 limits a pre_start_command' do
        expect do
          create('web', proc { start_command 'run' }, pre_start_command: 'setup', daemonize: true)
          create('db', proc { start_command 'run' }, pre_start_command: 'setup', daemonize: true)
        end.to output(pre_start_warning).to_stderr
      end

      it 'warns about a pre_start_command under its own key' do
        expect(Bluepill::Deprecation).to receive(:warn).with(:pre_start_command, Bluepill::ProcessFactory::PRE_START_COMMAND)
        create('web', proc { start_command 'run' }, pre_start_command: 'setup', daemonize: true)
      end

      context 'as root' do
        before { allow(::Process).to receive(:euid).and_return(0) }

        it 'warns once that 0.2.0 runs a process with a uid and no gid in the user\'s groups' do
          expect(Bluepill::Deprecation).to receive(:warn).twice.with(:uid_without_gid, Bluepill::ProcessFactory::UID_WITHOUT_GID).and_call_original
          expect do
            create('web', proc { start_command 'run' }, uid: 'deploy', gid: nil, daemonize: true)
            create('db', proc { start_command 'run' }, uid: 'deploy', daemonize: true)
          end.to output("DEPRECATION: #{Bluepill::ProcessFactory::UID_WITHOUT_GID}\n").to_stderr
        end

        it 'warns once that 0.2.0 runs a process with a uid and a gid in the user\'s other groups too' do
          expect(Bluepill::Deprecation).to receive(:warn).with(:uid_with_gid, Bluepill::ProcessFactory::UID_WITH_GID).and_call_original
          expect do
            create('web', proc { start_command 'run' }, uid: 'deploy', gid: 'deploy', daemonize: true)
          end.to output("DEPRECATION: #{Bluepill::ProcessFactory::UID_WITH_GID}\n").to_stderr
        end

        it 'warns about nothing for a process without a uid' do
          expect(Bluepill::Deprecation).not_to receive(:warn)
          create('web', proc { start_command 'run' }, uid: nil, gid: 'deploy', daemonize: true)
        end
      end

      it 'warns about no uid when bluepill does not run as root, since it switches no users' do
        allow(::Process).to receive(:euid).and_return(1000)
        expect(Bluepill::Deprecation).not_to receive(:warn)
        create('web', proc { start_command 'run' }, uid: 'deploy', daemonize: true)
      end

      it 'warns about nothing without a pre_start_command' do
        expect(Bluepill::Deprecation).not_to receive(:warn)
        create('web', proc { start_command 'run' }, pre_start_command: nil, pid_file: '/var/web.pid')
      end
    end

    it 'creates a process' do
      process = create('web', proc { start_command 'run' })
      expect(process).to be_a(Bluepill::Process)
      expect(process.name).to eq('web')
      expect(process.start_command).to eq('run')
    end

    it 'assigns a default pid file from the process name' do
      process = create('web server', proc { start_command 'run' })
      expect(process.pid_file).to eq('/pids/web_server.pid')
    end

    it 'replaces every unsafe character in the default pid file' do
      process = create('my web/server', proc { start_command 'run' })
      expect(process.pid_file).to eq('/pids/my_web_server.pid')
    end

    it 'assigns a default pid file from the group and process name' do
      process = create('web', proc { start_command 'run' }, group: 'my group')
      expect(process.pid_file).to eq('/pids/my_group_web.pid')
    end

    it 'keeps an explicit pid file' do
      process = create('web', proc { start_command 'run' }, pid_file: '/var/web.pid')
      expect(process.pid_file).to eq('/var/web.pid')
    end

    it 'exposes its attributes' do
      factory = Bluepill::ProcessFactory.new({uid: 'user'}, proc {})
      expect(factory.attributes).to eq(uid: 'user')
    end

    it 'creates a child process factory when monitoring children' do
      child_block = proc { stop_command 'halt' }
      process = create('web', proc do |p|
        p.start_command 'run'
        p.monitor_children(&child_block)
      end)
      expect(process.monitor_children).to be true
      expect(process.child_process_factory).to be_a(Bluepill::ProcessFactory)
      expect(process.child_process_factory.attributes).not_to have_key(:child_process_block)
      expect_any_instance_of(Bluepill::Process).to receive(:determine_initial_state)
      child = process.child_process_factory.create_child_process('child', 123, instance_double(Bluepill::Logger))
      expect(child.stop_command).to eq('halt')
    end

    it 'does not create a child process factory when monitor_children is false' do
      process = create('web', proc do |p|
        p.start_command 'run'
        p.monitor_children = false
      end)
      expect(process.child_process_factory).to be_nil
    end

    it 'does not create a child process factory otherwise' do
      process = create('web', proc { start_command 'run' })
      expect(process.child_process_factory).to be_nil
    end

    context 'validation' do
      it 'rejects duplicate process names in a group' do
        create('web', proc { start_command 'run' }, group: 'servers')
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create('web', proc { start_command 'run' }, group: 'servers')
        end
      end

      it 'rejects duplicate process names without a group' do
        create('web', proc { start_command 'run' })
        expect_config_error("Config Error: You have two entries for the process name 'web'\n") do
          create('web', proc { start_command 'run' }, pid_file: '/other.pid')
        end
      end

      it 'accepts the same process name in different groups' do
        create('web', proc { start_command 'run' }, group: 'a')
        expect { create('web', proc { start_command 'run' }, group: 'b') }.not_to raise_error
      end

      it 'accepts process names that only match when joined with a colon' do
        create('b:c', proc { start_command 'run' }, group: 'a')
        expect { create('c', proc { start_command 'run' }, group: 'a:b', pid_file: '/pids/c.pid') }.not_to raise_error
      end

      it 'treats Symbol and String group and process names alike' do
        create(:web, proc { start_command 'run' }, group: :servers)
        expect_config_error("Config Error: You have two entries for the process name 'web' in the group 'servers'\n") do
          create('web', proc { start_command 'run' }, group: 'servers', pid_file: '/other.pid')
        end
      end

      it 'tells a group without a name from no group' do
        create('web', proc { start_command 'run' })
        expect { create('web', proc { start_command 'run' }, group: '', pid_file: '/other.pid') }.not_to raise_error
      end

      it 'requires a start command' do
        expect_config_error("Config Error: You must specify a start_command for 'web'\n") do
          create('web', proc {})
        end
      end

      context 'without a known pid' do
        let(:warning) do
          "Config Warning: 'web' sets no daemonize, pid_file or pid_command, " \
            'so bluepill cannot find its pid unless start_command writes it to /pids/web.pid. ' \
            "Set daemonize = true if start_command runs in the foreground.\n"
        end

        it 'warns about a process that is not daemonized and uses the default pid file' do
          expect { create('web', proc { start_command 'run' }) }.to output(warning).to_stderr
        end

        it 'warns about a process with daemonize set to false' do
          expect { create('web', proc { start_command 'run' }, daemonize: false) }.to output(warning).to_stderr
        end

        it 'warns about a process with a nil pid command' do
          expect { create('web', proc { start_command 'run' }, pid_command: nil) }.to output(warning).to_stderr
        end

        it 'warns about a process that sets the default pid file itself' do
          block = proc do
            start_command 'run'
            pid_file '/pids/web.pid'
          end
          expect { create('web', block) }.to output(warning).to_stderr
        end

        it 'does not warn about a daemonized process' do
          expect { create('web', proc { start_command 'run' }, daemonize: true) }.not_to output.to_stderr
        end

        it 'does not warn about a process with a pid command' do
          expect { create('web', proc { start_command 'run' }, pid_command: 'pgrep web') }.not_to output.to_stderr
        end

        it 'does not warn about a process with its own pid file' do
          block = proc do
            start_command 'run'
            pid_file '/var/web.pid'
          end
          expect { create('web', block) }.not_to output.to_stderr
        end

        it 'does not warn about a pid file set before the default is assigned' do
          expect { create('web', proc { start_command 'run' }, pid_file: '/var/web.pid') }.not_to output.to_stderr
        end
      end

      it 'rejects duplicate pid files' do
        create('web', proc { start_command 'run' }, pid_file: '/shared.pid')
        expect_config_error("Config Error: You have two entries with the pid file: /shared.pid\n") do
          create('worker', proc { start_command 'run' }, pid_file: ' /shared.pid ')
        end
      end

      context 'stop_signals' do
        def create_with_signals(signals, grace_time)
          create('web', proc do
            start_command 'run'
            stop_signals signals
            stop_grace_time grace_time unless grace_time.nil?
          end)
        end

        it 'accepts valid stop signals' do
          process = create_with_signals([:quit, 5, :term], 10)
          expect(process.stop_signals).to eq([:quit, 5, :term])
        end

        it 'accepts a single stop signal' do
          process = create_with_signals([:term], 10)
          expect(process.stop_signals).to eq([:term])
        end

        it 'accepts Active Support durations as delays' do
          process = create_with_signals([:quit, 5.seconds, :term], 10)
          expect(process.stop_signals).to eq([:quit, 5, :term])
        end

        # Like a Fixnum before Ruby 2.4, which is an Integer but not an
        # instance of it
        it 'accepts any kind of Integer as a delay' do
          delay = double('delay', is_a?: true)
          expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
            create_with_signals([:quit, delay, :term], nil)
          end
        end

        it 'accepts a stop_grace_time just above the sum of the delays' do
          process = create_with_signals([:quit, 9, :term], 10)
          expect(process.stop_signals).to eq([:quit, 9, :term])
        end

        it 'rejects a stop_grace_time below the sum of the delays' do
          expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
            create_with_signals([:quit, 10, :term], 5)
          end
        end

        it 'requires signals to be symbols' do
          expect_config_error(/Expected a symbol \(signal\) at position 2 instead of 'term'/) do
            create_with_signals([:quit, 5, 'term'], 10)
          end
        end

        it 'requires delays to be numbers' do
          expect_config_error(/Expected a number \(delay\) at position 1 instead of 'five'/) do
            create_with_signals([:quit, 'five', :term], 10)
          end
        end

        it 'requires an odd number of elements' do
          expect_config_error("Config Error: Invalid stop_signals!  Expected an odd number of elements.\n") do
            create_with_signals([:quit, 5], 10)
          end
        end

        it 'requires a stop_grace_time' do
          expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
            create_with_signals([:quit, 5, :term], nil)
          end
        end

        it 'requires stop_grace_time to exceed the sum of the delays' do
          expect_config_error(/Stop_grace_time should be greater than the sum of stop_signals delays/) do
            create_with_signals([:quit, 5, :term, 5, :kill], 10)
          end
        end
      end
    end
  end

  describe '#create_child_process' do
    let(:logger) { instance_double(Bluepill::Logger) }
    let(:attributes) { {start_grace_time: 1, stop_grace_time: 2, restart_grace_time: 5, uid: 'user'} }

    it 'creates a child process with the grace times of its parent' do
      expect_any_instance_of(Bluepill::Process).to receive(:determine_initial_state)
      factory = Bluepill::ProcessFactory.new(attributes, proc { stop_command 'halt' })
      child = factory.create_child_process('child', 123, logger)

      expect(child).to be_a(Bluepill::Process)
      expect(child.name).to eq('child')
      expect(child.actual_pid).to eq(123)
      expect(child.logger).to eq(logger)
      expect(child.stop_command).to eq('halt')
      expect([child.start_grace_time, child.stop_grace_time, child.restart_grace_time]).to eq([1, 2, 5])
      expect(child.uid).to be_nil
    end

    it 'gives a child the default grace times when its parent sets none' do
      allow_any_instance_of(Bluepill::Process).to receive(:determine_initial_state)
      factory = Bluepill::ProcessFactory.new({}, proc { stop_command 'halt' })
      child = factory.create_child_process('child', 123, logger)
      expect([child.start_grace_time, child.stop_grace_time, child.restart_grace_time]).to eq([3, 3, 3])
    end

    it 'requires a stop command' do
      factory = Bluepill::ProcessFactory.new(attributes, proc {})
      message = "Config Error: Invalid child process monitor for child\nYou must specify a stop command to monitor child processes.\n"
      expect_config_error(message) do
        factory.create_child_process('child', 123, logger)
      end
    end
  end
end
