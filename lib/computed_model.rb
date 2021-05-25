# frozen_string_literal: true

require "computed_model/version"
require "computed_model/plan"
require "computed_model/dep_graph"
require "computed_model/model"

# ComputedModel is a universal batch loader which comes with a dependency-resolution algorithm.
#
# - Thanks to the dependency resolution, it allows you to the following trifecta at once, without breaking abstraction.
#   - Process information gathered from datasources (such as ActiveRecord) and return the derived one.
#   - Prevent N+1 problem via batch loading.
#   - Load only necessary data.
# - Can load data from multiple datasources.
# - Designed to be universal and datasource-independent.
#   For example, you can gather data from both HTTP and ActiveRecord and return the derived one.
#
# See {ComputedModel::Model} for basic usage.
module ComputedModel
  # An error raised when you tried to read from a loaded/computed attribute,
  # but that attribute isn't loaded by the batch loader.
  class NotLoaded < StandardError; end

  # An error raised when you tried to read from a loaded/computed attribute,
  # but that attribute isn't listed in the dependencies list.
  class ForbiddenDependency < StandardError; end

  # An error raised when the dependency graph contains a cycle.
  class CyclicDependency < StandardError; end

  # Normalizes dependency list as a hash.
  #
  # Normally you don't need to call it directly.
  # {ComputedModel::Model::ClassMethods#dependency}, {ComputedModel::Model::ClassMethods#bulk_load_and_compute}, and
  # {ComputedModel::NormalizableArray#normalized} will internally use this function.
  #
  # @param deps [Array<(Symbol, Hash)>, Hash, Symbol] dependency list
  # @return [Hash{Symbol=>Array}] normalized dependency hash
  # @raise [RuntimeError] if the dependency list contains values other than Symbol or Hash
  # @example
  #   ComputedModel.normalize_dependencies([:foo, :bar])
  #   # => { foo: [true], bar: [true] }
  #
  # @example
  #   ComputedModel.normalize_dependencies([:foo, bar: :baz])
  #   # => { foo: [true], bar: [true, :baz] }
  #
  # @example
  #   ComputedModel.normalize_dependencies(foo: -> (subdeps) { true })
  #   # => { foo: [#<Proc:...>] }
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

  # Removes `nil`, `true` and `false` from the given array.
  #
  # Normally you don't need to call it directly.
  # {ComputedModel::Model::ClassMethods#define_loader},
  # {ComputedModel::Model::ClassMethods#define_primary_loader}, and
  # {ComputedModel::NormalizableArray#normalized} will internally use this function.
  #
  # @param subdeps [Array] subfield selector list
  # @return [Array] the filtered one
  # @example
  #   ComputedModel.filter_subdeps([false, {}, true, nil, { foo: :bar }])
  #   # => [{}, { foo: :bar }]
  def self.filter_subdeps(subdeps)
    subdeps.select { |x| x && x != true }
  end

  # Convenience class to easily access normalized version of dependencies.
  #
  # You don't need to directly use it.
  #
  # - {ComputedModel::Model#current_subdeps} returns NormalizableArray.
  # - Procs passed to {ComputedModel::Model::ClassMethods#dependency} will receive NormalizeArray.
  class NormalizableArray < Array
    # Returns the normalized hash of the dependencies.
    # @return [Hash{Symbol=>Array}] the normalized hash of the dependencies
    # @raise [RuntimeError] if the list isn't valid as a dependency list.
    #   See {ComputedModel.normalize_dependencies} for details.
    def normalized
      @normalized ||= ComputedModel.normalize_dependencies(ComputedModel.filter_subdeps(self))
    end
  end
end
