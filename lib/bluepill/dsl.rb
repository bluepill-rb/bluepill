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
  # @param [Hash{Symbol => Object}, nil] options the application's options,
  #   as a Hash, which bluepill 0.3.0 doesn't take
  # @param [Hash{Symbol => Object}] keywords the application's options,
  #   such as :log_file, :foreground and :base_dir
  #
  # @yield [app] describes the application's processes
  # @yieldparam [AppProxy] app the application's proxy, which is also self
  # @yieldreturn [void]
  #
  # @return [void]
  #
  # @raise [ArgumentError] for options as a Hash and as keywords
  #
  # @api public
  def self.application(app_name, options = nil, **keywords, &block)
    Deprecation.check_keywords(options, keywords, "Bluepill.application #{app_name.to_s.inspect}")
    options ||= keywords
    app_proxy = AppProxy.new(app_name, options)
    Deprecation.check_ruby
    Deprecation.check_application_options(options)
    # instance_eval also passes the proxy to a block that takes an argument
    app_proxy.instance_eval(&block)
    app_proxy.app.load
  end
end
