# frozen_string_literal: true

require "computed_model/version"
require "computed_model/dep_graph"
require "computed_model/model"

module ComputedModel
  # An error raised when you tried to read from a loaded/computed attribute,
  # but that attribute isn't loaded by the batch loader.
  class NotLoaded < StandardError; end

  # A return value from {ComputedModel::ClassMethods#computing_plan}.
  Plan = Struct.new(:load_order, :subdeps_hash)

  # An object for storing procs for loaded attributes.
  Loader = Struct.new(:key_proc, :load_proc) # :nodoc:

  # @param deps [Array<(Symbol, Hash)>, Hash, Symbol]
  # @return [Hash{Symbol=>Array}]
  def self.normalize_dependencies(deps)
    normalized = {}
    deps = [deps] if deps.is_a?(Hash)
    Array(deps).each do |elem|
      case elem
      when Symbol
        normalized[elem] ||= []
      when Hash
        elem.each do |k, v|
          v = [v] if v.is_a?(Hash)
          normalized[k] ||= []
          normalized[k].push(*Array(v))
        end
      else; raise "Invalid dependency: #{elem.inspect}"
      end
    end
    normalized
  end
end
