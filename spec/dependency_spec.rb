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

      define_primary_loader :raw_user do |_subdeps, ids:, **_options|
        RawUser.where(id: ids).map { |raw_user| self.new(raw_user) }
      end
    end
  end
  before { stub_const("User", user_class) }

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
        }.to raise_error("Cyclic dependency for #name")
      end
    end

    context "when the dependency is not referenced" do
      it "doesn't raise an error" do
        expect {
          user_class.list(raw_user_ids, with: [])
        }.not_to raise_error
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
        }.to raise_error("Cyclic dependency for #name")
      end
    end

    context "when the dependency is not referenced" do
      it "doesn't raise an error" do
        expect {
          user_class.list(raw_user_ids, with: [])
        }.not_to raise_error
      end
    end
  end

  describe "unknown dependency name" do
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
end
