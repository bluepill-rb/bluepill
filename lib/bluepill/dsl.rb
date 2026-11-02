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
  # @param [Hash{Symbol => Object}] options the application's options, such
  #   as :log_file, :foreground and :base_dir
  #
  # @yield [app] describes the application's processes
  # @yieldparam [AppProxy] app the application's proxy, which is also self
  # @yieldreturn [void]
  #
  # @return [void]
  #
  # @api public
  def self.application(app_name, options = {}, &block)
    app_proxy = AppProxy.new(app_name, options)
    warn_unsupported_ruby
    # instance_eval also passes the proxy to a block that takes an argument
    app_proxy.instance_eval(&block)
    app_proxy.app.load
  end

  # Warn on a Ruby that bluepill 0.2 doesn't run on
  #
  # Bluepill 0.2.0 needs Ruby 2.0 or JRuby 9.0, and later 0.2 releases need
  # Ruby 2.7 or JRuby 9.4. JRuby 1.7 can run Ruby 2.0 code, so it's told
  # apart by its own version.
  #
  # @param [String] ruby_version the Ruby version, such as "1.9.3"
  # @param [String, nil] jruby_version the JRuby version, such as "1.7.27",
  #   or nil on another Ruby
  #
  # @return [void]
  #
  # @api private
  def self.warn_unsupported_ruby(ruby_version = RUBY_VERSION, jruby_version = defined?(JRUBY_VERSION) && JRUBY_VERSION)
    # Only Ruby 1.9 and JRuby 1.7 have a major version of 1
    return unless ruby_version.start_with?('1.') || (jruby_version && jruby_version.start_with?('1.'))

    message = "bluepill 0.2.0 needs Ruby 2.0 or JRuby 9.0, and later 0.2 releases need Ruby 2.7 or JRuby 9.4, so it won't run on Ruby #{ruby_version}" \
              "#{" (JRuby #{jruby_version})" if jruby_version}. Stay on bluepill 0.1 until you upgrade Ruby."
    Deprecation.warn(message, message)
  end
end
