module Bluepill
  class AppProxy
    APP_ATTRIBUTES = [:working_dir, :uid, :gid, :environment, :auto_start].freeze

    attr_accessor(*APP_ATTRIBUTES)
    attr_reader :app

    def initialize(app_name, options)
      @app = Application.new(app_name.to_s, options)
    end

    def process(process_name, &process_block)
      attributes = {}
      APP_ATTRIBUTES.each { |a| attributes[a] = send(a) }

      process_factory = ProcessFactory.new(attributes, process_block)

      process = process_factory.create_process(process_name, @app.pids_dir)
      group = process_factory.attributes.delete(:group)

      @app.add_process(process, group)
    end
  end
end
