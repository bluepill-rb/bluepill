module Bluepill
  # The self of the block given to {Bluepill.application}
  #
  # It sets defaults that every process of the application gets, and defines
  # the processes.
  #
  # @example
  #   Bluepill.application(:my_app) do |app|
  #     app.working_dir = '/srv/my_app'
  #     app.process('web') { |process| process.start_command = 'bin/server' }
  #   end
  #
  # @api public
  class AppProxy
    # The attributes that every process of the application gets, unless the
    # process sets its own
    APP_ATTRIBUTES = [:working_dir, :uid, :gid, :supplementary_groups, :environment, :auto_start].freeze

    # The directory that the application's processes start in
    #
    # @example
    #   app.working_dir = '/srv/my_app'
    #
    # @return [String, nil] the directory, or nil for the default
    #
    # @api public
    attr_accessor :working_dir

    # The user that the application's processes run as
    #
    # @example
    #   app.uid = 'deploy'
    #
    # @return [String, nil] the user's name, or nil for bluepill's own user
    #
    # @api public
    attr_accessor :uid

    # The group that the application's processes run as
    #
    # @example
    #   app.gid = 'deploy'
    #
    # @return [String, nil] the group's name, or nil for bluepill's own group
    #
    # @api public
    attr_accessor :gid

    # More groups that the application's processes run with
    #
    # The processes already get every group that their uid belongs to. These
    # are added to those.
    #
    # @example
    #   app.supplementary_groups = ['rvm', 'ssl-cert']
    #
    # @return [Array<String>, nil] the groups' names
    #
    # @api public
    attr_accessor :supplementary_groups

    # The environment variables that the application's processes get
    #
    # @example
    #   app.environment = {'RAILS_ENV' => 'production'}
    #
    # @return [Hash{#to_s => #to_s}, nil] the variables by name
    #
    # @api public
    attr_accessor :environment

    # Whether the application's processes start when bluepill loads
    #
    # @example
    #   app.auto_start = false
    #
    # @return [Boolean, nil] false to leave the processes unmonitored until
    #   they're started
    #
    # @api public
    attr_accessor :auto_start

    # Return the application that the config describes
    #
    # @return [Application] the application
    #
    # @api private
    attr_reader :app

    # Create the proxy of a new application
    #
    # @param [#to_s] app_name the application's name
    # @param [Hash{Symbol => Object}] options the application's options
    #
    # @return [void]
    #
    # @api private
    def initialize(app_name, options)
      @app = Application.new(app_name.to_s, options)
    end

    # Define a process of the application
    #
    # The block runs with self set to a {ProcessProxy}, and also gets the
    # proxy as an argument. The process starts with the application's
    # attributes, which the block can override.
    #
    # @example
    #   app.process('web') do |process|
    #     process.start_command = '/usr/bin/my_server'
    #     process.group = 'servers'
    #   end
    #
    # @param [String] process_name the process's name
    #
    # @yield [process] configures the process
    # @yieldparam [ProcessProxy] process the process's proxy, which is also
    #   self
    # @yieldreturn [void]
    #
    # @return [Array<Process>] the processes of the process's group
    #
    # @api public
    def process(process_name, &process_block)
      attributes = {} #: Hash[Symbol, untyped]
      APP_ATTRIBUTES.each { |a| attributes[a] = public_send(a) }

      process_factory = ProcessFactory.new(attributes, process_block)

      process = process_factory.create_process(process_name, @app.pids_dir)
      group = process_factory.attributes.delete(:group)

      @app.add_process(process, group)
    end
  end
end
