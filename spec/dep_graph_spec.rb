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

  describe '#tsort.plan' do
    it 'returns a sorted plan' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      plan = graph.tsort.plan([:field1, :field2, :field3])
      expect(plan.load_order.map(&:name)).to eq([:field4, :field2, :field1, :field3])
    end

    it 'returns a plan with only necessary fields' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: {} })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      plan = graph.tsort.plan([:field1])
      expect(plan.load_order.map(&:name)).to eq([:field4, :field2, :field1])
    end

    it 'collects the hash of subfield selectors' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: { a: 42 } })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: { b: 84 } })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field5, { field2: { c: 420 } })
      plan = graph.tsort.plan([:field1, :field5])
      expect(plan.load_order.map(&:name)).to eq([:field4, :field2, :field1, :field5])
      subfields_expect = {
        field4: [],
        field2: [{ a: 42 }, { c: 420 }],
        field1: [true],
        field5: [true]
      }
      expect(plan.load_order.map { |n| [n.name, n.subfields] }.to_h).to eq(subfields_expect)
    end

    it 'collects deps' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: { a: 42 } })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: { b: 84 } })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field5, { field2: { c: 420 } })
      plan = graph.tsort.plan([:field1, :field5])
      expect(plan.load_order.map(&:name)).to eq([:field4, :field2, :field1, :field5])
      deps_expect = {
        field4: Set[],
        field2: Set[],
        field1: Set[:field2],
        field5: Set[:field2]
      }
      expect(plan.load_order.map { |n| [n.name, n.deps] }.to_h).to eq(deps_expect)
    end

    it 'collects toplevel dependencies' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:computed, :field1, { field2: { a: 42 } })
      graph << ComputedModel::DepGraph::Node.new(:loaded, :field2, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field3, { field2: { b: 84 } })
      graph << ComputedModel::DepGraph::Node.new(:primary, :field4, {})
      graph << ComputedModel::DepGraph::Node.new(:computed, :field5, { field2: { c: 420 } })
      plan = graph.tsort.plan([:field1, :field5])
      expect(plan.load_order.map(&:name)).to eq([:field4, :field2, :field1, :field5])
      expect(plan.toplevel).to eq(Set[:field1, :field5])
    end

    it 'raises an error on multiple primary fields' do
      graph = ComputedModel::DepGraph.new
      graph << ComputedModel::DepGraph::Node.new(:primary, :field1, {})
      graph << ComputedModel::DepGraph::Node.new(:primary, :field2, {})
      expect {
        graph.tsort.plan([])
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
