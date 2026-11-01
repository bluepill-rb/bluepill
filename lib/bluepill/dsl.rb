module Bluepill
  def self.application(app_name, options = {}, &block)
    app_proxy = AppProxy.new(app_name, options)
    # instance_eval also passes the proxy to a block that takes an argument
    app_proxy.instance_eval(&block)
    app_proxy.app.load
  end
end
