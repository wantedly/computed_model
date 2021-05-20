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

  class CyclicDependency < StandardError; end

  # @param deps [Array<(Symbol, Hash)>, Hash, Symbol]
  # @return [Hash{Symbol=>Array}]
  def self.normalize_dependencies(deps)
    normalized = {}
    deps = [deps] if deps.is_a?(Hash)
    Array(deps).each do |elem|
      case elem
      when Symbol
        normalized[elem] ||= [true]
      when Hash
        elem.each do |k, v|
          v = [v] if v.is_a?(Hash)
          normalized[k] ||= []
          normalized[k].push(*Array(v))
          normalized[k].push(true) if v == []
        end
      else; raise "Invalid dependency: #{elem.inspect}"
      end
    end
    normalized
  end

  # @param subdeps [Array]
  # @return [Array]
  def self.filter_subdeps(subdeps)
    subdeps.select { |x| x && x != true }
  end

  # Convenience class to easily access normalized version of dependencies.
  class NormalizableArray < Array
    # @return [Hash{Symbol=>Array}]
    def normalized
      @normalized ||= ComputedModel.normalize_dependencies(ComputedModel.filter_subdeps(self))
    end
  end
end
