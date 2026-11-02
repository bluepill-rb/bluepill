# The parts of the daemons gem that bluepill uses, which bluepill used to
# get from blue-daemons, a fork of it. They're adapted from daemons'
# lib/daemons/daemonize.rb, which carries this notice:
#
# Copyright (c) 2005-2012 Thomas Uehlinger
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

module Bluepill
  # Turn the bluepill daemon, or a block, into a daemon process
  #
  # A daemon forks twice and starts a new session in between, so it has no
  # controlling terminal and init adopts it. It also leaves the directory
  # it started in, closes the files it inherited, and points its standard
  # streams at /dev/null.
  #
  # @api private
  module Daemonize
    # Raised when a daemon can't detach from its controlling terminal
    #
    # @api private
    class Error < RuntimeError; end

    # The highest file descriptor that close_io closes
    MAX_FD = 8191

    # Fork, retrying every 5 seconds while the system is out of processes
    #
    # @return [Integer, nil] the child's pid in the parent, nil in the child
    #
    # @api private
    def self.safefork
      loop do
        begin
          return fork
        rescue Errno::EWOULDBLOCK
          sleep 5
        end
      end
    end

    # Run a block in a daemon, and return the daemon's pid
    #
    # The forked processes exit with Process.exit!, never exit. They're
    # copies of the bluepill daemon made while it handles a command, so exit
    # would unwind the daemon's own stack in the copy, run its ensure
    # blocks against the socket it shares with the real daemon, and make
    # `bluepill start` hang (https://github.com/bluepill-rb/bluepill/issues/1).
    #
    # @param block [Proc] what the daemon runs, which usually execs
    # @param name [String, nil] the daemon's process title until then
    # @return [Integer] the daemon's pid, in the calling process
    #
    # @api private
    def self.call_as_daemon(block, name = nil)
      rd, wr = IO.pipe

      intermediate = safefork
      if intermediate
        wr.close
        pid = rd.read.to_i
        rd.close
        ::Process.waitpid(intermediate)
        return pid
      end

      rd.close
      detach
      if safefork
        wr.close
        ::Process.exit!(true)
      end

      wr.write(::Process.pid)
      wr.close
      become_daemon(name)
      block.call
      ::Process.exit!(true)
    end

    # Turn the calling process into a daemon
    #
    # The process that called it exits, so `bluepill load` returns, and the
    # daemon carries on from here.
    #
    # @return [Integer] the daemon's session id
    #
    # @api private
    def self.daemonize
      exit if safefork

      session = detach
      ::Process.exit!(true) if safefork

      become_daemon
      session
    end

    # Start a new session, which leaves the controlling terminal
    #
    # @return [Integer] the new session's id
    # @raise [Error] if there's no session to start
    #
    # @api private
    def self.detach
      session = ::Process.setsid
      raise Error, "cannot detach from controlling terminal" unless session

      # The session leader exits after the next fork, so the daemon can
      # never get a controlling terminal, and it ignores the hangup that
      # its exit sends
      Signal.trap("SIGHUP", "IGNORE")
      session
    end

    # Do what's left of becoming a daemon, in the process that stays
    #
    # @param name [String, nil] a new process title
    # @return [void]
    #
    # @api private
    def self.become_daemon(name = nil)
      $0 = name if name
      Dir.chdir("/") # don't keep the directory it started in in use
      close_io
      redirect_io
      srand # so the daemon and its parent don't share random numbers
    end

    # Close every file the process inherited, except the standard streams
    #
    # @return [void]
    #
    # @api private
    def self.close_io
      ObjectSpace.each_object(IO) do |io|
        next if [STDIN, STDOUT, STDERR].include?(io)

        begin
          io.close unless io.closed?
        rescue StandardError
          nil
        end
      end

      # And the file descriptors that no IO object holds
      (3..MAX_FD).each do |fd|
        begin
          IO.for_fd(fd).close
        rescue StandardError
          nil
        end
      end
    end

    # Point the standard streams at /dev/null
    #
    # @return [void]
    #
    # @api private
    def self.redirect_io
      [STDIN, STDOUT].each do |io|
        begin
          io.reopen(File::NULL)
        rescue StandardError
          nil
        end
      end

      begin
        STDERR.reopen(STDOUT)
      rescue StandardError
        nil
      end
      STDERR.sync = true
    end
  end
end
