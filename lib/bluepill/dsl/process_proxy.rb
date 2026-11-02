module Bluepill
  # The self of a process block in a config file
  #
  # Any of the process's attributes can be set with `name = value`,
  # `name value`, or `name!` for true, and read back with `name`. See
  # {Process::CONFIGURABLE_ATTRIBUTES} for the attributes a process has.
  #
  # @example
  #   app.process('web') do |process|
  #     process.start_command = '/usr/bin/my_server'
  #     process.daemonize!
  #     process.checks :mem_usage, every: 10.seconds, below: 100.megabytes
  #   end
  #
  # @api public
  class ProcessProxy
    # The attributes that bluepill 0.2.0 adds, which it knows along with
    # the ones bluepill 0.1 has
    #
    # @api private
    ATTRIBUTES_ADDED_IN_0_2 = [:post_start_command, :pre_stop_command, :post_stop_command, :notify_command, :hook_timeout].freeze

    # Return the attributes that the block set, by name
    #
    # @return [Hash{Symbol => Object}] the attributes
    #
    # @api private
    attr_reader :attributes

    # Return the checks that the block added, with their options, by name
    #
    # @return [Hash{Symbol => Hash{Symbol => Object}}] the checks
    #
    # @api private
    attr_reader :watches

    # Return the process's name
    #
    # @return [String] the name
    #
    # @api private
    attr_reader :name

    # Create the proxy of a process, and run its block
    #
    # @param [String] process_name the process's name
    # @param [Hash{Symbol => Object}] attributes the attributes the process
    #   starts with, which the block adds to
    # @param [Proc] process_block the block that configures the process
    #
    # @return [void]
    #
    # @api private
    def initialize(process_name, attributes, process_block)
      @name = process_name
      @attributes = attributes
      @watches = {}

      # instance_eval also passes the proxy to a block that takes an argument
      instance_eval(&process_block)
    end

    # Set or read an attribute of the process
    #
    # A name ending in `=`, or one given a value, sets the attribute. A name
    # ending in `!` sets it to true. A name alone reads an attribute that's
    # set.
    #
    # @example
    #   process.start_command = '/usr/bin/my_server'
    #   process.stop_grace_time 10.seconds
    #   process.daemonize!
    #   process.start_command # => "/usr/bin/my_server"
    #
    # @param [Symbol] name the attribute's name
    # @param [Array<Object>] args the value, if it's set
    #
    # @return [Object] the value that was set or read
    #
    # @raise [NoMethodError] for an attribute that isn't set, or more than one
    #   value
    #
    # @api public
    def method_missing(name, *args)
      attribute = name.to_s
      case args.size
      when 1
        value, = args
        set_attribute(attribute.chomp('=').to_sym, value)
      when 0
        if attribute.end_with?('!')
          set_attribute(attribute.chomp('!').to_sym, true)
        elsif @attributes.key?(name)
          @attributes.fetch(name)
        else
          super
        end
      else
        super
      end
    end

    # Return whether the proxy answers a name through method_missing
    #
    # Ruby turns a String name into a Symbol before calling this.
    #
    # @param [Symbol] name the method's name
    # @param [Boolean, nil] _include_private ignored
    #
    # @return [Boolean] true for a setter, a `name!`, or an attribute that's
    #   set
    #
    # @api private
    def respond_to_missing?(name, _include_private)
      ['=', '!'].include?(name[-1]) || @attributes.key?(name)
    end

    # Add a check of the process, or a trigger such as :flapping
    #
    # @example
    #   process.checks :cpu_usage, every: 10.seconds, below: 50, times: [3, 5]
    #   process.checks :flapping, times: 2, within: 30.seconds, retry_in: 7.seconds
    #
    # @param [Symbol] name the check's name, such as :mem_usage
    # @param [Hash{Symbol => Object}] options the check's options, such as
    #   :every, :below and :times
    #
    # @return [Hash{Symbol => Object}] the options
    #
    # @api public
    def checks(name, options = {})
      @watches[name] = options
    end

    # Monitor the process's children too
    #
    # The block configures each child the way a process block configures a
    # process. It must set a stop_command.
    #
    # @example
    #   process.monitor_children do |child|
    #     child.stop_command = 'kill -QUIT {{PID}}'
    #     child.checks :mem_usage, every: 10.seconds, below: 200.megabytes
    #   end
    #
    # @yield [child] configures each child
    # @yieldparam [ProcessProxy] child the child's proxy, which is also self
    # @yieldreturn [void]
    #
    # @return [Proc, nil] the block
    #
    # @api public
    def monitor_children(&child_process_block)
      @attributes[:monitor_children] = true
      @attributes[:child_process_block] = child_process_block
    end

    # Return whether bluepill 0.2.0 knows a process attribute
    #
    # It knows a process's configurable attributes, the group, and the
    # hooks it adds. It fails the config on any other.
    #
    # @param [Symbol] name the attribute's name
    #
    # @return [Boolean]
    #
    # @api private
    def self.known_in_0_2?(name)
      Process::CONFIGURABLE_ATTRIBUTES.include?(name) || name.eql?(:group) || ATTRIBUTES_ADDED_IN_0_2.include?(name)
    end

    # Create the process that the block described
    #
    # @return [Process] the process
    #
    # @api private
    def to_process
      Process.new(@name, @watches, @attributes)
    end

  private

    # Set an attribute, and warn about one that bluepill 0.2.0 doesn't know
    #
    # @param [Symbol] key the attribute's name
    # @param [Object] value its value
    #
    # @return [Object] the value
    #
    # @api private
    def set_attribute(key, value)
      unless self.class.known_in_0_2?(key)
        message = "bluepill 0.2.0 fails the config on the process attribute '#{key}', which bluepill doesn't know, " \
                  'where 0.1 ignores it. Remove it, or fix its name.'
        Deprecation.warn(message, message)
      end
      @attributes[key] = value
    end
  end
end
