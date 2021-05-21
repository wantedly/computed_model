# frozen_string_literal: true

require 'spec_helper'
require 'support/models/raw_user'
require 'support/models/raw_book'

RSpec.describe ComputedModel::Model do
  describe "simple inheritance" do
    it "mixes inherited fields" do
      base_klass = Class.new do
        include ComputedModel::Model

        attr_reader :id
        def initialize(id)
          @id = id
        end

        define_loader :field1, key: -> { id } do
          { 1 => 'foo', 2 => 'bar' }
        end

        def field2; raise NotImplementedError; end

        dependency :field2
        computed def field3
          "#{field2}-chocolate"
        end
      end

      subklass = Class.new(base_klass) do
        define_primary_loader :primary do
          [new(1), new(2)]
        end

        dependency :field1
        computed def field2
          "#{field1}-strawberry"
        end

        dependency :field3
        computed def field4
          "#{field3}-vanilla"
        end
      end

      objs = subklass.bulk_load_and_compute([:field4])
      expect(objs.map(&:field4)).to eq(['foo-strawberry-chocolate-vanilla', 'bar-strawberry-chocolate-vanilla'])
    end
  end

  describe "missing inclusion" do
    it "errors on missing inclusion in the indirectly included module" do
      indirect_module = Module.new do
        include ComputedModel::Model
      end

      expect {
        Class.new do
          include indirect_module

          computed def foo
            "foo"
          end
        end
      }.to raise_error(NoMethodError, /^undefined method `computed' for #<Class:.*>$/)
    end

    it 'allows redirecting helper methods via ActiveSupport::Concern' do
      indirect_module = Module.new do
        extend ActiveSupport::Concern
        include ComputedModel::Model
      end

      expect {
        Class.new do
          include indirect_module

          computed def foo
            "foo"
          end
        end
      }.not_to raise_error
    end
  end

  describe "invalid merger" do
    it "errors on multiple types on the same field" do
      base_klass = Class.new do
        include ComputedModel::Model

        attr_reader :id
        def initialize(id)
          @id = id
        end

        computed def field1; end
      end

      subklass = Class.new(base_klass) do
        define_primary_loader :primary do
          [new(1), new(2)]
        end

        define_loader :field1, key: -> { id } do
          { 1 => 'foo', 2 => 'bar' }
        end
      end

      expect {
        subklass.bulk_load_and_compute([])
      }.to raise_error(ArgumentError, 'Field field1 has multiple different types')
    end
  end
end
