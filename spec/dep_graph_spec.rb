require 'spec_helper'

RSpec.describe ComputedModel::DepGraph do
  describe '<<' do
    it 'raises an error on duplicate nodes' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :foo, {})
      expect {
        graph << ComputedModel::DepGraph::Node.new(:computed, :foo, {})
      }.to raise_error(ArgumentError, 'Field already declared: foo')
    end
  end

  describe '[]' do
    it 'returns the added node' do
      graph = ComputedModel::DepGraph.new
      foo = ComputedModel::DepGraph::Node.new(:computed, :foo, {})
      bar = ComputedModel::DepGraph::Node.new(:loaded, :bar, {})
      graph << foo
      graph << bar
      expect(graph[:foo]).to be(foo)
      expect(graph[:bar]).to be(bar)
    end

    it 'returns nil for unknown node name' do
      graph = ComputedModel::DepGraph.new
      foo = ComputedModel::DepGraph::Node.new(:computed, :foo, {})
      bar = ComputedModel::DepGraph::Node.new(:loaded, :bar, {})
      graph << foo
      graph << bar
      expect(graph[:baz]).to be_nil
    end
  end

  describe '#plan' do
    it 'returns a sorted plan' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      plan = graph.plan([:field1, :field2, :field3])
      expect(plan.load_order).to eq([:field4, :field2, :field1, :field3])
    end

    it 'returns a plan with only necessary fields' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      plan = graph.plan([:field1])
      expect(plan.load_order).to eq([:field4, :field2, :field1])
    end

    it 'collects subdeps_hash' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: { a: 42 } })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: { b: 84 } })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field5, { field2: { c: 420 } })
      plan = graph.plan([:field1, :field5])
      expect(plan.load_order).to eq([:field4, :field2, :field1, :field5])
      expect(plan.subdeps_hash).to eq({
                                        field1: [],
                                        field2: [{ a: 42 }, { c: 420 }],
                                        field4: [],
                                        field5: []
                                      })
    end

    it 'raises an error on multiple primary fields' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:primary, :field1, {})
      graph << ComputedModel::DepGraph::Node.new(:primary, :field2, {})
      expect {
        graph.plan([])
      }.to raise_error(RuntimeError, 'Multiple primary fields: [:field1, :field2]')
    end
  end

  describe '::Node' do
    describe '.new' do
      it 'raises an error on invalid type' do
        expect {
          ComputedModel::DepGraph::Node.new(:something, :foo, {})
        }.to raise_error(ArgumentError, 'invalid type: :something')
      end

      it 'raises an error on primary field with dependency' do
        expect {
          ComputedModel::DepGraph::Node.new(:primary, :foo, { bar: {} })
        }.to raise_error(ArgumentError, 'primary field cannot have dependency: foo')
      end
    end
  end
end
