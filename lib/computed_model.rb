# frozen_string_literal: true

require "computed_model/version"
require "computed_model/plan"
require "computed_model/dep_graph"
require "computed_model/model"

module ComputedModel
  # An error raised when you tried to read from a loaded/computed attribute,
  # but that attribute isn't loaded by the batch loader.
  class NotLoaded < StandardError; end

  # An error raised when you tried to read from a loaded/computed attribute,
  # but that attribute isn't listed in the dependencies list.
  class ForbiddenDependency < StandardError; end

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
