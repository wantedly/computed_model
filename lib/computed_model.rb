# frozen_string_literal: true

require "computed_model/version"
require 'set'

module ComputedModel
  class NotLoaded < StandardError; end

  Plan = Struct.new(:load_order, :subdeps_hash)

  module ClassMethods
    # @param deps [Array]
    def dependency(*deps)
      @__computed_model_next_dependency ||= []
      @__computed_model_next_dependency.push(*deps)
    end

    # @param meth_name [Symbol]
    def computed(meth_name)
      var_name = :"@#{meth_name}"
      meth_name_orig = :"#{meth_name}_orig"
      compute_meth_name = :"compute_#{meth_name}"

      @__computed_model_dependencies[meth_name] = ComputedModel.normalize_dependencies(@__computed_model_next_dependency)
      remove_instance_variable(:@__computed_model_next_dependency)

      alias_method meth_name_orig, meth_name
      define_method(meth_name) do
        raise NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)
        instance_variable_get(var_name)
      end
      define_method(compute_meth_name) do
        instance_variable_set(var_name, send(meth_name_orig))
      end
      if public_method_defined?(meth_name_orig)
        public meth_name
      elsif protected_method_defined?(meth_name_orig)
        protected meth_name
      elsif private_method_defined?(meth_name_orig)
        private meth_name
      end

      meth_name
    end

    # @param methods [Array<Symbol>]
    # @param to [Symbol]
    # @param allow_nil [nil, Boolean]
    # @param prefix [nil, Symbol]
    # @param include_subdeps [nil, Boolean]
    # @return [void]
    def delegate_dependency(*methods, to:, allow_nil: nil, prefix: nil, include_subdeps: nil)
      method_prefix = prefix ? "#{prefix_}" : ""
      methods.each do |meth_name|
        pmeth_name = :"#{method_prefix}#{meth_name}"
        if include_subdeps
          dependency to=>meth_name
        else
          dependency to
        end
        if allow_nil
          define_method(pmeth_name) do
            send(to)&.public_send(meth_name)
          end
        else
          define_method(pmeth_name) do
            send(to).public_send(meth_name)
          end
        end
        computed pmeth_name
      end
    end

    # @param meth_name [Symbol]
    # @yieldparam objects [Array]
    # @yieldparam options [Hash]
    # @yieldreturn [void]
    def define_loader(meth_name, &block)
      raise ArgumentError, "No block given" unless block

      var_name = :"@#{meth_name}"

      @__computed_model_loaders[meth_name] = block

      define_method(meth_name) do
        raise NotLoaded, "the field #{meth_name} is not loaded" unless instance_variable_defined?(var_name)
        instance_variable_get(var_name)
      end
      attr_writer meth_name
    end

    # @param objs [Array]
    # @param deps [Array]
    def bulk_load_and_compute(objs, deps, **options)
      objs = objs.dup
      plan = computing_plan(deps)
      plan.load_order.each do |dep_name|
        if @__computed_model_dependencies.key?(dep_name)
          objs.each do |obj|
            obj.send(:"compute_#{dep_name}")
          end
        elsif @__computed_model_loaders.key?(dep_name)
          @__computed_model_loaders[dep_name].call(objs, plan.subdeps_hash[dep_name], **options)
        else
          raise "No dependency info for #{self}##{dep_name}"
        end
        objs.reject! { |obj| !obj.computed_model_error.nil? }
      end
    end

    # @param deps [Array]
    # @return [Plan]
    def computing_plan(deps)
      normalized = ComputedModel.normalize_dependencies(deps)
      load_order = []
      subdeps_hash = {}
      visiting = Set[]
      visited = Set[]
      normalized.each do |dep_name, dep_subdeps|
        computing_plan_dfs(dep_name, dep_subdeps, load_order, subdeps_hash, visiting, visited)
      end

      Plan.new(load_order, subdeps_hash)
    end

    # @param meth_name [Symbol]
    # @param meth_subdeps [Array]
    # @param load_order [Array<Symbol>]
    # @param subdeps_hash [Hash{Symbol=>Array}]
    # @param visiting [Set<Symbol>]
    # @param visited [Set<Symbol>]
    private def computing_plan_dfs(meth_name, meth_subdeps, load_order, subdeps_hash, visiting, visited)
      (subdeps_hash[meth_name] ||= []).push(*meth_subdeps)
      return if visited.include?(meth_name)
      raise "Cyclic dependency for #{self}##{meth_name}" if visiting.include?(meth_name)
      visiting.add(meth_name)

      if @__computed_model_dependencies.key?(meth_name)
        @__computed_model_dependencies[meth_name].each do |dep_name, dep_subdeps|
          computing_plan_dfs(dep_name, dep_subdeps, load_order, subdeps_hash, visiting, visited)
        end
      elsif @__computed_model_loaders.key?(meth_name)
      else
        raise "No dependency info for #{self}##{meth_name}"
      end

      load_order << meth_name
      visiting.delete(meth_name)
      visited.add(meth_name)
    end
  end

  # @param deps [Array<Symbol, Hash>]
  # @return [Hash{Symbol=>Array}]
  def self.normalize_dependencies(deps)
    normalized = {}
    deps.each do |elem|
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

  attr_accessor :computed_model_error

  def self.included(klass)
    super
    klass.extend ClassMethods
    klass.instance_variable_set(:@__computed_model_dependencies, {})
    klass.instance_variable_set(:@__computed_model_loaders, {})
  end
end
