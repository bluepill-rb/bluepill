# frozen_string_literal: true

require "tmpdir"

describe Bluepill::Controller do
  let(:base_dir) { Dir.mktmpdir }
  let(:controller) { described_class.new(base_dir: base_dir, log_file: "/var/log/bluepill.log") }

  after { FileUtils.remove_entry(base_dir) }

  def touch(path, contents = "") = File.write(File.join(base_dir, path), contents)

  # Leave an application's socket, and its pid file unless pid is nil
  def touch_app(name, pid = nil)
    touch("socks/#{name}.sock")
    touch("pids/#{name}.pid", pid) if pid
  end

  def files_left = Dir[File.join(base_dir, "*", "*")]

  def raise_bluepill_error(error_class, message, exit_status = 1)
    raise_error(an_instance_of(error_class).and(having_attributes(message: message, exit_status: exit_status)))
  end

  def stub_daemon(command, response)
    allow(Bluepill::Socket).to receive(:client_command)
      .with(base_dir, "app", "version").and_return(Bluepill::Version.to_s)
    allow(Bluepill::Socket).to receive(:client_command)
      .with(base_dir, "app", command).and_return(response)
  end

  describe "#initialize" do
    it "keeps its options" do
      expect(controller).to have_attributes(log_file: "/var/log/bluepill.log", base_dir: base_dir)
    end

    it "has the paths in the base dir" do
      expect(controller.base_directory).to have_attributes(class: Bluepill::BaseDirectory, path: base_dir)
    end

    it "creates the directories" do
      controller
      expect(%w[socks pids].collect { |dir| File.directory?(File.join(base_dir, dir)) }).to eq([true, true])
    end

    context "with applications" do
      before { controller }

      it "keeps the files of a running application" do
        touch_app("app", "123")
        allow(Bluepill::System).to receive(:pid_alive?).with(123).and_return(true)
        described_class.new(base_dir: base_dir)
        expect(files_left).to contain_exactly(File.join(base_dir, "socks", "app.sock"), File.join(base_dir, "pids", "app.pid"))
      end

      it "keeps checking applications after a running one" do
        touch_app("a", "123")
        touch_app("b")
        allow(Bluepill::System).to receive(:pid_alive?).with(123).and_return(true)
        described_class.new(base_dir: base_dir)
        expect(controller.running_applications).to eq(["a"])
      end

      it "removes the files of an application that is not running" do
        touch_app("dead", "456")
        allow(Bluepill::System).to receive(:pid_alive?).with(456).and_return(false)
        described_class.new(base_dir: base_dir)
        expect(files_left).to eq([])
      end

      it "removes the socket of an application without a pid file" do
        touch_app("nopid")
        described_class.new(base_dir: base_dir)
        expect(files_left).to eq([])
      end

      it "removes the files of an application with an empty pid file" do
        touch_app("empty", "")
        described_class.new(base_dir: base_dir)
        expect(files_left).to eq([])
      end
    end
  end

  describe "#running_applications" do
    it "lists the applications that have a socket" do
      controller
      touch("socks/app.sock")
      touch("socks/other.txt")
      expect(controller.running_applications).to eq(["app"])
    end
  end

  describe "#handle_command" do
    it "prints the status" do
      stub_daemon("status:web", "web:\n")
      expect { controller.handle_command("app", "status", "web") }.to output("web:\n").to_stdout
    end

    it "prints the status of every process" do
      stub_daemon("status", "web:\n")
      expect { controller.handle_command("app", "status") }.to output("web:\n").to_stdout
    end

    describe "process commands" do
      it "prints the affected processes" do
        stub_daemon("start:web", ["web:first", "web:second"])
        expect { controller.handle_command("app", "start", "web") }.to output(
          "Sent start to:\n  web:first\n  web:second\n"
        ).to_stdout
      end

      it "says when no process was affected" do
        stub_daemon("stop", [])
        expect { controller.handle_command("app", "stop") }.to output("No processes effected\n").to_stdout
      end
    end

    it "raises on an unknown command" do
      expect { controller.handle_command("app", "bogus") }.to raise_bluepill_error(
        Bluepill::UnknownCommandError, "Unknown command `bogus` (or application `bogus` has not been loaded yet)"
      )
    end
  end

  describe "#handle_command quit" do
    before do
      controller
      write_pid("789")
      allow(Bluepill::System).to receive(:pid_alive?).and_return(false)
      allow(::Process).to receive(:kill)
      # Keep the examples that don't check the output quiet
      allow($stdout).to receive(:puts)
    end

    def write_pid(pid) = touch("pids/app.pid", pid)

    def quit = controller.handle_command("app", "quit")

    context "when the daemon is running" do
      before { allow(Bluepill::System).to receive(:pid_alive?).with(789).and_return(true) }

      it "kills it" do
        quit
        expect(::Process).to have_received(:kill).with("TERM", 789)
      end

      it "says so" do
        expect { quit }.to output("Killing bluepilld[789]\n").to_stdout
      end
    end

    context "when the daemon has pid 1, as in a container" do
      before do
        write_pid("1")
        allow(Bluepill::System).to receive(:pid_alive?).with(1).and_return(true)
      end

      it "kills it" do
        quit
        expect(::Process).to have_received(:kill).with("TERM", 1)
      end

      it "says so" do
        expect { quit }.to output("Killing bluepilld[1]\n").to_stdout
      end
    end

    context "without a pid file" do
      before { File.delete(File.join(base_dir, "pids", "app.pid")) }

      it "says the daemon is not running" do
        expect { quit }.to output("bluepilld[false] not running\n").to_stdout
      end

      it "does not check a pid" do
        quit
        expect(Bluepill::System).not_to have_received(:pid_alive?)
      end
    end

    context "when the daemon is not running" do
      it "says so" do
        expect { quit }.to output("bluepilld[789] not running\n").to_stdout
      end

      it "checks its pid" do
        quit
        expect(Bluepill::System).to have_received(:pid_alive?).with(789)
      end

      it "does not kill it" do
        quit
        expect(::Process).not_to have_received(:kill)
      end
    end

    ["", "garbage"].each do |contents|
      context "when the pid file holds #{contents.inspect}" do
        before { write_pid(contents) }

        it "says the daemon is not running" do
          expect { quit }.to output("bluepilld[false] not running\n").to_stdout
        end

        it "does not check a pid" do
          quit
          expect(Bluepill::System).not_to have_received(:pid_alive?)
        end

        it "does not kill anything" do
          quit
          expect(::Process).not_to have_received(:kill)
        end
      end
    end
  end

  describe "#handle_command log" do
    # What the CLI runs to tail a log file through grep
    def tail(path, pattern) = ["sh", "-c", 'tail -n 100 -f "$1" | grep -E "$2"', "sh", path, pattern]

    before do
      # Keep the examples that don't check the output quiet
      allow($stdout).to receive(:puts)
      allow(Kernel).to receive(:exec)
    end

    context "with the log file reported by the daemon" do
      before { stub_daemon("log_file", "/tmp/app.log") }

      it "says what it tails" do
        expect { controller.handle_command("app", "log", "web") }.to output("Tailing log for web...\n").to_stdout
      end

      it "tails the log file" do
        controller.handle_command("app", "log", "web")
        expect(Kernel).to have_received(:exec).with(*tail("/tmp/app.log", '\[.*app:web.*'))
      end
    end

    it "uses only the first argument as the pattern" do
      stub_daemon("log_file", "/tmp/app.log")
      controller.handle_command("app", "log", "web", "extra")
      expect(Kernel).to have_received(:exec).with(*tail("/tmp/app.log", '\[.*app:web.*'))
    end

    it "passes the log file and the pattern to the shell as arguments" do
      stub_daemon("log_file", "/tmp/my app's $(log)")
      controller.handle_command("app", "log", "it's")
      expect(Kernel).to have_received(:exec).with(*tail("/tmp/my app's $(log)", "\\[.*app:it's.*"))
    end

    it "tails an empty path without any log file" do
      stub_daemon("log_file", nil)
      controller.log_file = nil
      controller.handle_command("app", :log)
      expect(Kernel).to have_received(:exec).with(*tail("", '\[.*app.*'))
    end

    it "falls back to its own log file when the daemon logs to syslog" do
      stub_daemon("log_file", nil)
      controller.handle_command("app", :log)
      expect(Kernel).to have_received(:exec).with(*tail("/var/log/bluepill.log", '\[.*app.*'))
    end

    it "falls back to its own log file" do
      stub_daemon("log_file", " ")
      controller.handle_command("app", :log)
      expect(Kernel).to have_received(:exec).with(*tail("/var/log/bluepill.log", '\[.*app.*'))
    end
  end

  describe "#send_to_daemon" do
    it "returns the response of the daemon" do
      stub_daemon("status:web:first", "up")
      expect(controller.send_to_daemon("app", :status, "web", "first")).to eq("up")
    end

    # Send status to the daemon, and return the Bluepill::Error it raises
    def send_error
      controller.send_to_daemon("app", :status)
    rescue Bluepill::Error => e
      e
    end

    # Make the daemon answer the version command with version, or raise it
    def answer_version(version)
      stubbed = allow(Bluepill::Socket).to receive(:client_command).with(base_dir, "app", "version")
      version.is_a?(Class) ? stubbed.and_raise(version) : stubbed.and_return(version)
    end

    # What a daemon's version answer is after Marshal sends it to the CLI
    def through_marshal(version) = Marshal.load(Marshal.dump(version))

    def out_of_date = "The running version of your daemon seems to be out of date."

    context "when the daemon answers with an error" do
      let(:error) { RuntimeError.new("boom") }

      before { stub_daemon("status", error) }

      it "raises a DaemonError with the error and its backtrace" do
        error.set_backtrace(["a.rb:1", "b.rb:2"])
        expect(send_error).to have_attributes(
          class: Bluepill::DaemonError, message: "Received error from server:\n#{error.inspect}\na.rb:1\nb.rb:2", exit_status: 8
        )
      end

      it "keeps the daemon's error" do
        expect(send_error.daemon_error).to be(error)
      end

      it "leaves out a backtrace the error doesn't have" do
        expect(send_error.message).to eq("Received error from server:\n#{error.inspect}")
      end
    end

    it "raises when the daemon refuses the connection" do
      allow(Bluepill::Socket).to receive(:client_command).and_raise(Errno::ECONNREFUSED)
      expect(send_error).to have_attributes(class: Bluepill::ConnectionError, message: "Connection Refused: Server is not running")
    end

    context "when the daemon runs a version" do
      before { stub_daemon("status", "up") }

      it "accepts the same version, through Marshal" do
        answer_version(through_marshal(Bluepill::Application.allocate.version))
        expect(controller.send_to_daemon("app", :status)).to eq("up")
      end

      it "raises when the version differs" do
        answer_version("0.0.1")
        expect(send_error).to have_attributes(
          class: Bluepill::VersionMismatchError, message: "#{out_of_date}\nDaemon Version: 0.0.1, CLI Version: #{Bluepill::Version}", exit_status: 1
        )
      end

      it "raises when a daemon older than 0.3.0 answers with its Version module" do
        answer_version(through_marshal(Bluepill::Version))
        expect(send_error).to have_attributes(class: Bluepill::VersionMismatchError, message: out_of_date)
      end

      it "raises when the daemon does not understand the version command" do
        answer_version(ArgumentError)
        expect(send_error).to have_attributes(class: Bluepill::VersionMismatchError, message: out_of_date)
      end
    end
  end

  describe "#grep_pattern" do
    it "matches the application" do
      expect(controller.grep_pattern("app")).to eq('\[.*app.*')
    end

    it "matches the application and an escaped query" do
      expect(controller.grep_pattern("app", "a.b")).to eq('\[.*app:a\.b.*')
    end
  end
end
