# frozen_string_literal: true

require 'set'

module ComputedModel
  # A plan for batch loading. Created by {ComputedModel::DepGraph::Sorted#plan}.
  #
  # @api private
  class Plan
    # @return [Array<ComputedModel::Plan::Node>] fields in load order
    attr_reader :load_order
    # @return [Set<Symbol>] toplevel dependencies
    attr_reader :toplevel

    # @param load_order [Array<ComputedModel::Plan::Node>] fields in load order
    # @param toplevel [Set<Symbol>] toplevel dependencies
    def initialize(load_order, toplevel)
      @load_order = load_order.freeze
      @nodes = load_order.map { |node| [node.name, node] }.to_h
      @toplevel = toplevel
    end

    # @param name [Symbol]
    # @return [ComputedModel::Plan::Node, nil]
    def [](name)
      @nodes[name]
    end

    # A set of information necessary to invoke the loader or the computed def.
    class Node
      # @return [Symbol] field name
      attr_reader :name
      # @return [Set<Symbol>] set of dependency names
      attr_reader :deps
      # @return [ComputedModel::NormalizableArray] subfield selectors, payloads sent to the dependency
      attr_reader :subfields

      # @param name [Symbol] field name
      # @param deps [Set<Symbol>] set of dependency names
      # @param subfields [ComputedModel::NormalizableArray] subfield selectors, payloads sent to the dependency
      def initialize(name, deps, subfields)
        @name = name
        @deps = deps
        @subfields = subfields
      end
    end
  end
end
