# frozen_string_literal: true

module Bluepill
  # Load an application from a config file
  #
  # The block describes the application's processes. It runs with self set
  # to an {AppProxy}, and also gets the proxy as an argument. Bluepill then
  # loads the application, which starts its daemon.
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
  # @param [Array(Hash{Symbol => Object})] args the application's options,
  #   such as :log_file, :foreground and :base_dir, as keyword arguments
  #
  # @yield [app] describes the application's processes
  # @yieldparam [AppProxy] app the application's proxy, which is also self
  # @yieldreturn [void]
  #
  # @return [void]
  #
  # @raise [ArgumentError] for more than one Hash of options
  #
  # @api public
  def self.application(app_name, *args, &block)
    raise ArgumentError, "wrong number of arguments (given #{args.size + 1}, expected 1..2)" if args.size > 1

    app_proxy = AppProxy.new(app_name, args.fetch(0, AppProxy::NO_OPTIONS))
    Deprecation.check_ruby
    Deprecation.check_keywords(args, "Bluepill.application #{app_name.to_s.inspect}")
    Deprecation.check_application_options(args.fetch(0, AppProxy::NO_OPTIONS))
    # instance_eval also passes the proxy to a block that takes an argument
    app_proxy.instance_eval(&block)
    app_proxy.app.load
  end

  class << self
    # Mark a Hash passed as keywords, so a Hash passed without ** can warn
    ruby2_keywords(:application)
  end
end
