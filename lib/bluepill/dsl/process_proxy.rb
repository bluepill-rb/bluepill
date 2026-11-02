# frozen_string_literal: true

require "bluepill/util/levenshtein"

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
    # set. Only the attributes a process has can be set, so a misspelled one
    # fails when the config loads instead of being ignored.
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
    # @raise [NoMethodError] for an attribute a process doesn't have, one
    #   that isn't set yet, or more than one value
    #
    # @api public
    def method_missing(name, *args)
      key, reader, value = attribute_call(name, args)
      if key
        return @attributes.fetch(key) if reader && @attributes.key?(key)

        unknown_attribute!(key) unless self.class.attribute?(key)
        return @attributes[key] = value unless reader
      end
      # A call with the wrong number of values, or the reader of a known
      # attribute that isn't set yet
      super
    end

    # Return whether the proxy answers a name through method_missing
    #
    # Ruby turns a String name into a Symbol before calling this.
    #
    # @param [Symbol] name the method's name
    # @param [Boolean, nil] _include_private ignored
    #
    # @return [Boolean] true for the setter or `name!` of an attribute a
    #   process has, or the reader of one that's set
    #
    # @api private
    def respond_to_missing?(name, _include_private)
      attribute = name.to_s
      key = attribute.sub(/[=!]\z/, "")
      return @attributes.key?(name) if key.eql?(attribute)

      self.class.attribute?(key.to_sym)
    end

    # Return whether a process has an attribute that a config can set
    #
    # These are a process's configurable attributes, and the group it's in.
    #
    # @param [Symbol] name the attribute's name
    #
    # @return [Boolean] true for an attribute a config can set
    #
    # @api private
    def self.attribute?(name)
      attribute_names.include?(name)
    end

    # Return the attributes a config can set on a process
    #
    # @return [Array<Symbol>] a process's configurable attributes, and :group
    #
    # @api private
    def self.attribute_names
      Process::CONFIGURABLE_ATTRIBUTES + [:group]
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

    # Create the process that the block described
    #
    # @return [Process] the process
    #
    # @api private
    def to_process
      Process.new(@name, @watches, @attributes)
    end

    private

    # Return the attribute a call names, and the value it sets
    #
    # A name alone with no value reads the attribute. A name ending in `=`,
    # or one alone, sets it to one value, and a name ending in `!` sets it
    # to true with none.
    #
    # @param [Symbol] name the method's name
    # @param [Array<Object>] args the call's arguments
    #
    # @return [Array(Symbol, Boolean), Array(Symbol, Boolean, Object), nil]
    #   the attribute's name, whether the call reads it, and the value a
    #   setter sets, or nil for a call with the wrong number of values
    #
    # @api private
    def attribute_call(name, args)
      attribute = name.to_s
      key = attribute.sub(/[=!]\z/, "").to_sym
      return [key, true] if args.empty? && key.to_s.eql?(attribute)

      bang = attribute.end_with?("!")
      value, = args
      [key, false, bang || value] if args.size.equal?(bang ? 0 : 1)
    end

    # Fail on an attribute a process doesn't have
    #
    # The message names the process and the attribute, and the closest
    # attribute a process has, when there's one close enough.
    #
    # @param [Symbol] key the attribute's name
    #
    # @return [void] it never returns
    #
    # @raise [NoMethodError] always
    #
    # @api private
    def unknown_attribute!(key)
      message = "Unknown attribute '#{key}' for process '#{@name}'"
      suggestion = suggest(key)
      message += ". Did you mean '#{suggestion}'?" if suggestion
      raise NoMethodError.new(message, key) # steep:ignore ArgumentTypeMismatch
    end

    # Return the attribute a process has that's closest to a misspelled one
    #
    # The closest is the one the fewest edits away, if that's at most a
    # third of the misspelled name's length. Ruby's did_you_mean would do,
    # but Bundler leaves it out on Rubies before 2.7, so bluepill compares
    # the names itself and suggests the same attribute on every Ruby.
    #
    # @param [Symbol] key the misspelled attribute
    #
    # @return [String, nil] the closest attribute, or nil
    #
    # @api private
    def suggest(key)
      word = key.to_s
      distances = self.class.attribute_names.collect { |name| [Util.levenshtein_distance(word, name.to_s), name.to_s] } #: Array[[Integer, String]]
      closest = distances.min #: [Integer, String]
      distance, name = closest
      name if distance <= word.length / 3
    end
  end
end
