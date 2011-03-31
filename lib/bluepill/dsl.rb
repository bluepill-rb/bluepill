# -*- encoding: utf-8 -*-

module Bluepill
  def self.application(app_name, options = {}, &block)
    app_proxy = AppProxy.new(app_name, options)
    yield(app_proxy)
    app_proxy.app.load
  end
end
