# frozen_string_literal: true

# Prints what loading bluepill adds to Ruby's own classes and modules, one
# line each: the bluepill modules it mixes into them, and the methods it
# defines on them in its own files. Run by spec/core_extensions_spec.rb.
lib = File.expand_path("../../lib", __dir__)

# Ruby's own classes and modules, in every Ruby and JRuby bluepill supports.
# (Walking every constant instead trips over JRuby's Java packages.)
core = [
  BasicObject, Object, Kernel, Module, Class, Comparable, Enumerable,
  NilClass, TrueClass, FalseClass, Numeric, Integer, Float, Rational, Complex,
  String, Symbol, Array, Hash, Range, Regexp, MatchData, Struct, Enumerator,
  Proc, Method, UnboundMethod, Time, Random, IO, File, Dir, Process, Signal,
  Thread, Mutex, Exception, StandardError, Encoding, Math, Marshal, GC,
  ObjectSpace
]

ancestors = {}
core.each do |mod|
  ancestors[mod] = mod.ancestors
  ancestors[mod.singleton_class] = mod.singleton_class.ancestors
end

$LOAD_PATH.unshift(lib)
require "bluepill"
Dir[File.join(lib, "bluepill", "**", "*.rb")].each { |file| require file }

def bluepill_method?(mod, name, lib)
  location = mod.instance_method(name).source_location
  location&.first&.start_with?(lib)
end

added = []
ancestors.each do |mod, before|
  (mod.ancestors - before).each do |included|
    next unless included.name.to_s.start_with?("Bluepill")
    # Integer and Float get Numeric's modules too, but not from bluepill
    next if mod.is_a?(Class) && mod.superclass && mod.superclass.ancestors.include?(included)

    added << "#{mod.inspect} includes #{included.inspect}"
  end
  (mod.instance_methods(false) + mod.private_instance_methods(false)).each do |name|
    added << "#{mod.inspect}##{name}" if bluepill_method?(mod, name, lib)
  end
end

puts added.sort
