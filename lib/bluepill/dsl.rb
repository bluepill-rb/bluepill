# frozen_string_literal: true

module Bluepill
  # Load an application from a config file
  #
  # The block describes the application's processes. It runs with self set
  # to an {AppProxy}, and also gets the proxy as an argument. Bluepill then
  # loads the application, which starts its daemon. A {Bluepill::Error},
  # such as a {ConfigError} for a mistake in the config, prints its message
  # and exits with its exit_status, which is 6 for a ConfigError. A
  # ConfigError's message starts with the pill file's line, as in
  # "app.pill.rb:5: Unknown attribute ...".
  #
  # @example
  #   Bluepill.application(:my_app, log_file: '/var/log/bluepill.log') do |app|
  #     app.process('web') do |process|
  #       process.start_command = '/usr/bin/my_server'
  #       process.pid_file = '/var/run/my_server.pid'
  #     end
  #   end
  #
  # @param [#to_s] app_name the application's name
  # @param [Hash{Symbol => Object}] options the application's options, such
  #   as log_file:, foreground: and base_dir:
  #
  # @yield [app] describes the application's processes
  # @yieldparam [AppProxy] app the application's proxy, which is also self
  # @yieldreturn [void]
  #
  # @return [void]
  #
  # @api public
  def self.application(app_name, **options, &)
    app_proxy = AppProxy.new(app_name, **options)
    # evaluate also passes the proxy to a block that takes an argument, and
    # turns a misspelled attribute into a ConfigError
    app_proxy.evaluate(&)
    app_proxy.app.load
  rescue Error => e
    location = e.location if e.is_a?(ConfigError)
    $stderr.puts(location ? "#{location}: #{e}" : e)
    exit(e.exit_status)
  end
end
