# frozen_string_literal: true

module Bluepill
  # The paths in bluepill's base directory
  #
  # The daemons' sockets are in socks, and their pid files are in pids,
  # next to a directory for each application's processes. The CLI and the
  # daemon both find them here.
  #
  # @api private
  class BaseDirectory
    # The extension of a daemon's socket
    SOCKET_EXTENSION = ".sock"

    attr_reader :path

    # @!attribute [r] path
    #   The base directory
    #
    #   @return [String]
    #
    #   @api private

    # Create the paths for a base directory
    #
    # @param [String] path the base directory
    #
    # @return [void]
    #
    # @api private
    def initialize(path) = @path = path

    # Return the directory with the daemons' sockets
    #
    # @return [String]
    #
    # @api private
    def sockets_dir = File.join(path, "socks")

    # Return the directory with the daemons' pid files
    #
    # @return [String]
    #
    # @api private
    def pids_dir = File.join(path, "pids")

    # Return the socket that an application's daemon listens on
    #
    # @param [String] app the application's name
    #
    # @return [String]
    #
    # @api private
    def socket_file(app) = File.join(sockets_dir, "#{app}#{SOCKET_EXTENSION}")

    # Return an application's daemon's pid file
    #
    # @param [String] app the application's name
    #
    # @return [String]
    #
    # @api private
    def pid_file(app) = File.join(pids_dir, "#{app}.pid")

    # Return the directory with the pid files of an application's processes
    #
    # @param [String] app the application's name
    #
    # @return [String]
    #
    # @api private
    def process_pids_dir(app) = File.join(pids_dir, app)

    # Return the names of the applications with a socket
    #
    # @return [Array<String>]
    #
    # @api private
    def socket_names
      Dir[socket_file("*")].collect { |socket| File.basename(socket, SOCKET_EXTENSION) }
    end
  end
end
