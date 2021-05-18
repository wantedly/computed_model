# frozen_string_literal: true

require 'set'

module ComputedModel
  # A plan for batch loading. Created by {ComputedModel::DepGraph#plan}.
  class Plan
    # @return [Array<ComputedModel::Plan::Node>] fields in load order
    attr_reader :load_order
    # @return [Set<Symbol>] toplevel dependencies
    attr_reader :toplevel

    # @param load_order [Array<ComputedModel::Plan::Node>] fields in load order
    # @param toplevel [Set<Symbol>] toplevel dependencies
    def initialize(load_order, toplevel)
      @load_order = load_order.freeze
      @toplevel = toplevel
    end

    # A set of information necessary to invoke the loader or the computed def.
    class Node
      # @return [Symbol] field name
      attr_reader :name
      # @return [Set<Symbol>] set of dependency names
      attr_reader :deps
      # @return [Array] a payload given to the loader
      attr_reader :subdeps

      # @param name [Symbol] field name
      # @param deps [Set<Symbol>] set of dependency names
      # @param subdeps [Array] a payload given to the loader
      def initialize(name, deps, subdeps)
        @name = name
        @deps = deps
        @subdeps = subdeps
      end
    end
  end
end
