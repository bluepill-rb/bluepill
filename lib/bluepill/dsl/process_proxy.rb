module Bluepill
  class ProcessProxy
    attr_reader :attributes, :watches, :name

    def initialize(process_name, attributes, process_block)
      @name = process_name
      @attributes = attributes
      @watches = {}

      # instance_eval also passes the proxy to a block that takes an argument
      instance_eval(&process_block)
    end

    def method_missing(name, *args)
      attribute = name.to_s
      case args.size
      when 1
        value, = args
        @attributes[attribute.chomp('=').to_sym] = value
      when 0
        if attribute.end_with?('!')
          @attributes[attribute.chomp('!').to_sym] = true
        elsif @attributes.key?(name)
          @attributes.fetch(name)
        else
          super
        end
      else
        super
      end
    end

    # Ruby turns a String name into a Symbol before calling this
    def respond_to_missing?(name, _include_private)
      ['=', '!'].include?(name[-1]) || @attributes.key?(name)
    end

    def checks(name, options = {})
      @watches[name] = options
    end

    def monitor_children(&child_process_block)
      @attributes[:monitor_children] = true
      @attributes[:child_process_block] = child_process_block
    end

    def to_process
      Process.new(@name, @watches, @attributes)
    end
  end
end
