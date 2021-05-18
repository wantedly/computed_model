# frozen_string_literal: true

require 'set'

module ComputedModel
  # A dependency graph representation used within ComputedModel::Model.
  # Usually you don't need to use this class directly.
  #
  # @example
  #   graph = ComputedModel::DepGraph.new
  #   graph << ComputedModel::DepGraph::Node.new(:computed, :foo, { bar: [] })
  #   graph << ComputedModel::DepGraph::Node.new(:loaded, :bar, {})
  #   plan = graph.plan([:foo])
  class DepGraph
    def initialize
      @nodes = {}
    end

    # Returns the node with the specified name.
    #
    # @param name [Symbol] the name of the node
    # @return [Node, nil]
    #
    # @example
    #   graph = ComputedModel::DepGraph.new
    #   graph[:foo]
    def [](name)
      @nodes[name]
    end

    # Adds the new node.
    #
    # @param node [Node]
    # @return [void]
    # @raise [ArgumentError] when the node already exists
    #
    # @example
    #   graph = ComputedModel::DepGraph.new
    #   graph << ComputedModel::DepGraph::Node.new(:computed, :foo, {})
    def <<(node)
      raise ArgumentError, "Field already declared: #{node.name}" if @nodes.key?(node.name)

      @nodes[node.name] = node
    end

    # Computes the plan for the given requirements.
    #
    # @param deps [Array] the list of required nodes. Each dependency can optionally include subdeps hashes.
    # @return [ComputedModel::Plan]
    #
    # @example Plain dependencies
    #   graph.plan([:field1, :field2])
    #
    # @example Dependencies with subdeps
    #   graph.plan([:field1, field2: { optional_field: {} }])
    def plan(deps)
      normalized = ComputedModel.normalize_dependencies(deps)
      load_order = []
      subdeps_hash = {}
      visiting = Set[]
      visited = Set[]

      @nodes.each_value do |node|
        next unless node.type == :primary

        load_order << node.name
        visiting.add node.name
        visited.add node.name
        subdeps_hash[node.name] ||= []
      end

      raise ArgumentError, 'No primary loader defined' if load_order.empty?
      raise "Multiple primary fields: #{load_order.inspect}" if load_order.size > 1

      normalized.each do |name, subdeps|
        plan_dfs(name, subdeps, load_order, subdeps_hash, visiting, visited)
      end

      nodes = load_order.map do |name|
        deps = @nodes[name].edges.values.map(&:name).to_set
        ComputedModel::Plan::Node.new(name, deps, subdeps_hash[name] || [])
      end
      ComputedModel::Plan.new(nodes, normalized.keys.to_set)
    end

    # @param name [Symbol]
    # @param subdeps [Array]
    # @param load_order [Array<Symbol>]
    # @param subdeps_hash [Hash{Symbol=>Array}]
    # @param visiting [Set<Symbol>]
    # @param visited [Set<Symbol>]
    private def plan_dfs(name, subdeps, load_order, subdeps_hash, visiting, visited)
      (subdeps_hash[name] ||= []).push(*subdeps)
      return if visited.include?(name)
      raise "Cyclic dependency for ##{name}" if visiting.include?(name)
      raise "No dependency info for ##{name}" unless @nodes.key?(name)

      visiting.add(name)

      @nodes[name].edges.each_value do |edge|
        plan_dfs(edge.name, edge.spec, load_order, subdeps_hash, visiting, visited)
      end

      load_order << name
      visiting.delete(name)
      visited.add(name)
    end

    # A node in the dependency graph. That is, a field in a computed model.
    #
    # @example computed node with plain dependencies
    #   Node.new(:computed, :field1, { field2: [], field3: [] })
    # @example computed node with subdeps
    #   Node.new(:computed, :field1, { field2: [:foo, bar: []], field3: [] })
    # @example loaded and primary dependencies
    #   Node.new(:loaded, :field1, {})
    #   Node.new(:primary, :field1, {})
    class Node
      # @return [Symbol] the type of the node. One of :computed, :loaded and :primary.
      attr_reader :type
      # @return [Symbol] the name of the node.
      attr_reader :name
      # @return [Hash{Symbol => Edge}] edges indexed by its name.
      attr_reader :edges

      ALLOWED_TYPES = %i[computed loaded primary].freeze
      private_constant :ALLOWED_TYPES

      # @param type [Symbol] the type of the node. One of :computed, :loaded and :primary.
      # @param name [Symbol] the name of the node.
      # @param edges [Array<(Symbol, Hash)>, Hash, Symbol] list of edges.
      def initialize(type, name, edges)
        raise ArgumentError, "invalid type: #{type.inspect}" unless ALLOWED_TYPES.include?(type)

        edges = ComputedModel.normalize_dependencies(edges)
        raise ArgumentError, "primary field cannot have dependency: #{name}" if type == :primary && edges.size > 0

        @type = type
        @name = name
        @edges = edges.map { |k, v| [k, Edge.new(k, v)] }.to_h.freeze
      end
    end

    # An edge in the dependency graph. That is, a dependency declaration in a computed model.
    class Edge
      # @return [Symbol] the name of the dependency (not the dependent)
      attr_reader :name
      # @return [Array] an auxiliary data called subdeps
      attr_reader :spec

      # @param name [Symbol] the name of the dependency (not the dependent)
      # @param spec [Array] an auxiliary data called subdeps
      def initialize(name, spec)
        @name = name
        @spec = Array(spec)
      end
    end
  end
end
