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
  #   plan = graph.tsort.plan([:foo])
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

    # Preprocess the graph by topological sorting. This is a necessary step for loader planning.
    #
    # @return [ComputedModel::DepGraph::Sorted]
    #
    # @example
    #   graph = ComputedModel::DepGraph.new
    #   graph << ComputedModel::DepGraph::Node.new(:computed, :foo, { bar: [] })
    #   graph << ComputedModel::DepGraph::Node.new(:loaded, :bar, {})
    #   sorted = graph.tsort
    def tsort
      load_order = []
      visiting = Set[]
      visited = Set[]

      @nodes.each_value do |node|
        next unless node.type == :primary

        load_order << node.name
        visiting.add node.name
        visited.add node.name
      end

      raise ArgumentError, 'No primary loader defined' if load_order.empty?
      raise "Multiple primary fields: #{load_order.inspect}" if load_order.size > 1

      @nodes.each_value do |node|
        tsort_dfs(node.name, load_order, visiting, visited)
      end

      nodes_in_order = load_order.reverse.map { |name| @nodes[name] }
      ComputedModel::DepGraph::Sorted.new(self, nodes_in_order)
    end

    private def tsort_dfs(name, load_order, visiting, visited)
      return if visited.include?(name)
      raise ComputedModel::CyclicDependency, "Cyclic dependency for ##{name}" if visiting.include?(name)
      raise "No dependency info for ##{name}" unless @nodes.key?(name)

      visiting.add(name)

      @nodes[name].edges.each_value do |edge|
        tsort_dfs(edge.name, load_order, visiting, visited)
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
      # @param spec [Array, Proc] an auxiliary data called subdeps
      def initialize(name, spec)
        @name = name
        @spec = Array(spec)
      end

      # @param subdeps [Array]
      # @return [Array, nil]
      def evaluate(subdeps)
        return @spec if @spec.all? { |specelem| !specelem.respond_to?(:call) }

        evaluated = []
        @spec.each do |specelem|
          if specelem.respond_to?(:call)
            ret = specelem.call(subdeps)
            if ret.is_a?(Array)
              evaluated.push(*ret)
            else
              evaluated << ret
            end
          else
            evaluated << specelem
          end
        end
        evaluated
      end
    end

    # A preprocessed graph with topologically sorted order.
    #
    # Generated by {ComputedModel::DepGraph#tsort}.
    class Sorted
      # @return [ComputedModel::DepGraph]
      attr_reader :original
      # @return [Array<ComputedModel::DepGraph::Node>]
      attr_reader :nodes_in_order

      # @param original [ComputedModel::DepGraph]
      # @param nodes_in_order [Array<ComputedModel::DepGraph::Node>]
      def initialize(original, nodes_in_order)
        @original = original
        @nodes_in_order = nodes_in_order
      end

      # Computes the plan for the given requirements.
      #
      # @param deps [Array] the list of required nodes. Each dependency can optionally include subdeps hashes.
      # @return [ComputedModel::Plan]
      #
      # @example Plain dependencies
      #   sorted.plan([:field1, :field2])
      #
      # @example Dependencies with subdeps
      #   sorted.plan([:field1, field2: { optional_field: {} }])
      def plan(deps)
        normalized = ComputedModel.normalize_dependencies(deps)
        subdeps_hash = {}
        uses = Set[]
        plan_nodes = []

        normalized.each do |name, subdeps|
          raise "No dependency info for ##{name}" unless @original[name]

          uses.add(name)
          (subdeps_hash[name] ||= []).unshift(*subdeps)
        end
        @nodes_in_order.each do |node|
          uses.add(node.name) if node.type == :primary
          next unless uses.include?(node.name)

          node_subdeps = ComputedModel::NormalizableArray.new(subdeps_hash[node.name] || [])
          deps = Set[]
          node.edges.each_value do |edge|
            specval = edge.evaluate(node_subdeps)
            if specval.any?
              deps.add(edge.name)
              uses.add(edge.name)
              (subdeps_hash[edge.name] ||= []).unshift(*specval)
            end
          end
          plan_nodes.push(ComputedModel::Plan::Node.new(node.name, deps, node_subdeps))
        end
        ComputedModel::Plan.new(plan_nodes.reverse, normalized.keys.to_set)
      end
    end
  end
end
