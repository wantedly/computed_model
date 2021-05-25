# frozen_string_literal: true

require 'spec_helper'
require 'support/models/raw_user'
require 'support/models/raw_book'

RSpec.describe ComputedModel do
  let!(:raw_user1) { create(:raw_user, name: "User One") }
  let!(:raw_user2) { create(:raw_user, name: "User Two") }
  let!(:raw_user3) { create(:raw_user, name: "User Three") }
  let!(:raw_user4) { create(:raw_user, name: "User Four") }
  let(:raw_user_ids) { [raw_user1, raw_user2, raw_user3, raw_user4].map(&:id) }
  before { raw_user3.destroy! }

  let(:user_class) do
    Class.new do
      def self.name; "User"; end
      def self.to_s; "User"; end

      include ComputedModel::Model

      attr_reader :id

      def initialize(raw_user)
        @id = raw_user.id
        @raw_user = raw_user
      end

      def self.list(ids, with:)
        bulk_load_and_compute(with, ids: ids)
      end

      define_primary_loader :raw_user do |_subfields, ids:, **_options|
        RawUser.where(id: ids).map { |raw_user| self.new(raw_user) }
      end
    end
  end
  before { stub_const("User", user_class) }

  describe "conditional dependency" do
    before do
      user_class.module_eval do
        computed def foo; "foo"; end

        dependency foo: -> (subfields) { subfields.normalized[:require_foo]&.any? }
        computed def bar
          f = current_deps.include?(:foo) ? foo : "not foo"
          ["bar", current_deps, current_subfields, f]
        end
      end
    end

    it "doesn't require foo if require_foo is missing" do
      u = user_class.list(raw_user_ids, with: { bar: true }).first
      expect(u.bar).to eq(["bar", Set[], [true], "not foo"])
      expect(u.instance_variable_defined?(:@foo)).to be(false)
    end

    it "requires foo if require_foo is given" do
      u = user_class.list(raw_user_ids, with: { bar: { require_foo: true } }).first
      expect(u.bar).to eq(["bar", Set[:foo], [{ require_foo: true }], "foo"])
      expect(u.instance_variable_defined?(:@foo)).to be(true)
    end
  end

  describe "incorrect define_primary_loader implementation" do
    before do
      user_class.module_eval do
        def initialize(raw_user)
          @id = raw_user.id
          # @raw_user = raw_user
        end
      end
    end
    it "raises NotLoaded" do
      u = user_class.list(raw_user_ids, with: [:raw_user]).first
      expect { u.raw_user }.to raise_error(ComputedModel::NotLoaded, 'the field raw_user is not loaded')
    end
  end

  describe "subfield selectors mapping" do
    before do
      user_class.module_eval do
        computed def foo
          ["foo", current_subfields]
        end

        dependency foo: -> (subfields) { subfields.normalized[:foospec] }
        computed def bar
          f = current_deps.include?(:foo) ? foo : ["not foo"]
          ["bar", current_deps, current_subfields, f]
        end
      end
    end

    it "doesn't require foo if foospec is missing" do
      u = user_class.list(raw_user_ids, with: { bar: [] }).first
      expect(u.bar).to eq(["bar", Set[], [true], ["not foo"]])
      expect(u.instance_variable_defined?(:@foo)).to be(false)
    end

    it "doesn't require foo if foospec is false" do
      u = user_class.list(raw_user_ids, with: { bar: [{ foospec: false }] }).first
      expect(u.bar).to eq(["bar", Set[], [{ foospec: false }], ["not foo"]])
      expect(u.instance_variable_defined?(:@foo)).to be(false)
    end

    it "requires foo if foospec is given" do
      u = user_class.list(raw_user_ids, with: { bar: { foospec: { payload_for_foo: :something } } }).first
      expect(u.bar).to eq(["bar", Set[:foo], [{ foospec: { payload_for_foo: :something } }], ["foo", [{ payload_for_foo: :something }]]])
      expect(u.instance_variable_defined?(:@foo)).to be(true)
    end
  end

  describe "subfield selectors passthrough" do
    before do
      user_class.module_eval do
        computed def foo
          ["foo", current_subfields]
        end

        dependency foo: [-> (subfields) { subfields }, { fixed_payload: :egg }]
        computed def bar
          f = current_deps.include?(:foo) ? foo : ["not foo"]
          ["bar", current_deps, current_subfields, f]
        end
      end
    end

    it "passes subfields through to foo" do
      u = user_class.list(raw_user_ids, with: { bar: { payload_for_foo: :something } }).first
      expect(u.bar).to eq(["bar", Set[:foo], [{ payload_for_foo: :something }], ["foo", [{ payload_for_foo: :something }, { fixed_payload: :egg }]]])
      expect(u.instance_variable_defined?(:@foo)).to be(true)
    end
  end

  describe "cyclic dependency" do
    before do
      user_class.module_eval do
        dependency :name
        computed def fancy_name
          "#{name}-san"
        end

        dependency :fancy_name
        computed def name
          fancy_name.sub(/-san$/, '')
        end
      end
    end

    context "when the dependency is referenced" do
      it "raises an error" do
        expect {
          user_class.list(raw_user_ids, with: [:name])
        }.to raise_error(ComputedModel::CyclicDependency, "Cyclic dependency for #fancy_name")
      end
    end

    context "when the dependency is not referenced" do
      it "raises an error" do
        expect {
          user_class.list(raw_user_ids, with: [])
        }.to raise_error(ComputedModel::CyclicDependency, "Cyclic dependency for #fancy_name")
      end
    end

    context "when verify_dependencies is called" do
      it "raises an error" do
        expect {
          user_class.module_eval do
            verify_dependencies
          end
        }.to raise_error(ComputedModel::CyclicDependency, "Cyclic dependency for #fancy_name")
      end
    end
  end

  describe "self-referential dependency" do
    before do
      user_class.module_eval do
        dependency :name
        computed def name
          "foo"
        end
      end
    end

    context "when the dependency is referenced" do
      it "raises an error" do
        expect {
          user_class.list(raw_user_ids, with: [:name])
        }.to raise_error(ComputedModel::CyclicDependency, "Cyclic dependency for #name")
      end
    end

    context "when the dependency is not referenced" do
      it "raises an error" do
        expect {
          user_class.list(raw_user_ids, with: [])
        }.to raise_error(ComputedModel::CyclicDependency, "Cyclic dependency for #name")
      end
    end

    context "when verify_dependencies is called" do
      it "raises an error" do
        expect {
          user_class.module_eval do
            verify_dependencies
          end
        }.to raise_error(ComputedModel::CyclicDependency, "Cyclic dependency for #name")
      end
    end
  end

  describe "unknown indirect dependency name" do
    before do
      user_class.module_eval do
        dependency :namae
        computed def fancy_name
          "#{namae}-san"
        end
      end
    end

    it "raises an error" do
      expect {
        user_class.list(raw_user_ids, with: [:fancy_name])
      }.to raise_error("No dependency info for #namae")
    end
  end

  describe "unknown dependency name" do
    it "raises an error" do
      expect {
        user_class.list(raw_user_ids, with: [:namae])
      }.to raise_error("No dependency info for #namae")
    end
  end

  describe "dependency visibility" do
    context "when public" do
      before do
        user_class.module_eval do
          delegate_dependency :name, to: :raw_user

          def compare_fancy_name(other)
            fancy_name == other.fancy_name
          end

          def very_fancy_name
            "#{fancy_name}-sama"
          end

          public

          dependency :name
          computed def fancy_name
            "#{name}-san"
          end
        end
      end

      it "makes the computed method public" do
        u1, u2 = user_class.list(raw_user_ids, with: [:fancy_name])
        expect(u1.fancy_name).to eq("User One-san")
        expect(u1.compare_fancy_name(u2)).to eq(false)
        expect(u1.very_fancy_name).to eq("User One-san-sama")
      end
    end

    context "when protected" do
      before do
        user_class.module_eval do
          delegate_dependency :name, to: :raw_user

          def compare_fancy_name(other)
            fancy_name == other.fancy_name
          end

          def very_fancy_name
            "#{fancy_name}-sama"
          end

          protected

          dependency :name
          computed def fancy_name
            "#{name}-san"
          end
        end
      end

      it "makes the computed method protected" do
        u1, u2 = user_class.list(raw_user_ids, with: [:fancy_name])
        expect {
          u1.fancy_name
        }.to raise_error(NoMethodError, /protected method `fancy_name' called/)
        expect(u1.compare_fancy_name(u2)).to eq(false)
        expect(u1.very_fancy_name).to eq("User One-san-sama")
      end
    end

    context "when private" do
      before do
        user_class.module_eval do
          delegate_dependency :name, to: :raw_user

          def compare_fancy_name(other)
            fancy_name == other.fancy_name
          end

          def very_fancy_name
            "#{fancy_name}-sama"
          end

          private

          dependency :name
          computed def fancy_name
            "#{name}-san"
          end
        end
      end

      it "makes the computed method private" do
        u1, u2 = user_class.list(raw_user_ids, with: [:fancy_name])
        expect {
          u1.fancy_name
        }.to raise_error(NoMethodError, /private method `fancy_name' called/)
        expect {
          u1.compare_fancy_name(u2)
        }.to raise_error(NoMethodError, /private method `fancy_name' called/)
        expect(u1.very_fancy_name).to eq("User One-san-sama")
      end
    end
  end

  describe "field dependency description" do
    before do
      user_class.module_eval do
        dependency
        computed def special1
          "Hello, "
        end

        dependency
        computed def special2
          "world!"
        end
      end
    end

    it "accepts symbol dependency" do
      user_class.module_eval do
        dependency :special1
        computed def message
          "#{special1}"
        end
      end
      u = user_class.list(raw_user_ids, with: [:message]).first
      expect(u.message).to eq("Hello, ")
    end

    it "accepts multiple symbol dependencies at once" do
      user_class.module_eval do
        dependency :special1, :special2
        computed def message
          "#{special1}#{special2}"
        end
      end
      u = user_class.list(raw_user_ids, with: [:message]).first
      expect(u.message).to eq("Hello, world!")
    end

    it "accepts multiple symbol dependencies in multiple dependency statements" do
      user_class.module_eval do
        dependency :special1
        dependency :special2
        computed def message
          "#{special1}#{special2}"
        end
      end
      u = user_class.list(raw_user_ids, with: [:message]).first
      expect(u.message).to eq("Hello, world!")
    end

    it "accepts hash dependencies as kwargs" do
      user_class.module_eval do
        dependency special1: {}, special2: {}
        computed def message
          "#{special1}#{special2}"
        end
      end
      u = user_class.list(raw_user_ids, with: [:message]).first
      expect(u.message).to eq("Hello, world!")
    end

    it "accepts hash dependencies as an option hash" do
      user_class.module_eval do
        dependency({ special1: {}, special2: {} })
        computed def message
          "#{special1}#{special2}"
        end
      end
      u = user_class.list(raw_user_ids, with: [:message]).first
      expect(u.message).to eq("Hello, world!")
    end

    it "raises an error for values other than Symbol or Hash" do
      expect {
        user_class.module_eval do
          dependency([:special1, :special2])
          computed def message
            "#{special1}#{special2}"
          end
        end
      }.to raise_error("Invalid dependency: [:special1, :special2]")
    end

    it "accepts computed field with no dependency declaration" do
      user_class.module_eval do
        computed def foo
          "foo"
        end
      end
      u = user_class.list(raw_user_ids, with: [:foo]).first
      expect(u.foo).to eq("foo")
    end
  end

  describe "loader description" do
    describe "missing block" do
      it "raises an error" do
        expect {
          user_class.module_eval do
            define_loader :foo, key: -> { id }
          end
        }.to raise_error(ArgumentError, "No block given")
      end
    end
  end

  describe "primary loader description" do
    describe "missing block" do
      it "raises an error" do
        expect {
          user_class.module_eval do
            define_primary_loader :foo
          end
        }.to raise_error(ArgumentError, "No block given")
      end
    end
  end

  describe "missing primary loader" do
    let(:user_class) do
      Class.new do
        def self.name; "User"; end
        def self.to_s; "User"; end

        include ComputedModel::Model

        attr_reader :id

        def initialize(raw_user)
          @id = raw_user.id
          @raw_user = raw_user
        end

        def self.list(ids, with:)
          bulk_load_and_compute(with, ids: ids)
        end
      end
    end

    it "raises an error" do
      expect {
        user_class.list(raw_user_ids, with: [])
      }.to raise_error(ArgumentError, 'No primary loader defined')
    end
  end

  describe "dependency before loader" do
    before do
      user_class.module_eval do
        delegate_dependency :name, to: :raw_user

        dependency :name
        define_loader :fancy_name, key: -> { self } do |objs, _subfields|
          objs.map { |obj| [obj, "#{obj.name}-san"] }.to_h
        end
      end
    end

    it "is consumed by define_loader" do
      u = user_class.list(raw_user_ids, with: [:fancy_name]).first
      expect(u.fancy_name).to eq("User One-san")
    end
  end

  describe "dependency before primary loader" do
    it "raises an error" do
      expect {
        Class.new do
          include ComputedModel::Model
          dependency :foo
          define_primary_loader(:bar) {}
        end
      }.to raise_error(ArgumentError, 'primary field cannot have a dependency')
    end
  end
end
