# -*- encoding: utf-8 -*-

module Bluepill
  class ProcessProxy
    attr_reader :attributes, :watches, :name
    def initialize(process_name, attributes, process_block)
      @name = process_name
      @attributes = attributes
      @watches = {}

      process_block.call(self)
    end

    def method_missing(name, *args)
      if args.size == 1 && name.to_s =~ /^(.*)=$/
        @attributes[$1.to_sym] = args.first
      elsif args.empty? && @attributes.key?(name.to_sym)
        @attributes[name.to_sym]
      else
        super
      end
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
