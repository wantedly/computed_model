# frozen_string_literal: true

RSpec.describe ComputedModel do
  class self::Sandbox
    class RawUser
      attr_accessor :id
      attr_accessor :name

      def initialize(id:, name: nil)
        @id = id
        @name = name
      end

      def self.list(ids)
        ids.map { |id| USERS[id] }.compact
      end

      USERS = [
        RawUser.new(id: 1, name: "User One"),
        RawUser.new(id: 2, name: "User Two"),
        RawUser.new(id: 4, name: "User Four"),
      ].map { |user| [user.id, user] }.to_h
    end

    class User
      include ComputedModel

      attr_reader :id

      def initialize(id)
        @id = id
      end

      def self.list(ids, with:)
        objs = ids.map { |id| User.new(id) }
        bulk_load_and_compute(objs, Array(with) + [:raw_user])
        objs.reject! { |u| u.raw_user.nil? }
        objs
      end

      define_loader :raw_user do |users, _subdeps, **_options|
        user_ids = users.map(&:id)
        raw_users = RawUser.list(user_ids).map { |u| [u.id, u] }.to_h
        users.each do |user|
          user.raw_user = raw_users[user.id]
        end
      end

      # TODO: this allow_nil is weird; resolve inconsistency
      delegate_dependency :name, to: :raw_user, allow_nil: true

      dependency :name
      computed def fancy_name
        "#{name}-san"
      end
    end
  end

  it "has a version number" do
    expect(ComputedModel::VERSION).not_to be nil
  end

  context "when fetched with raw_user" do
    let(:users) { self.class::Sandbox::User.list([1, 2, 3, 4], with: [:raw_user]) }
    it "fetches raw_user.name" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.raw_user.name}).to contain_exactly("User One", "User Two", "User Four")
    end

    it "doesn't fetch name" do
      expect {
        users[0].name
      }.to raise_error(ComputedModel::NotLoaded, "the field name is not loaded")
    end
  end

  context "when fetched with name" do
    let(:users) { self.class::Sandbox::User.list([1, 2, 3, 4], with: [:name]) }
    it "fetches raw_user.name" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.raw_user.name}).to contain_exactly("User One", "User Two", "User Four")
    end

    it "fetches name" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.name}).to contain_exactly("User One", "User Two", "User Four")
    end

    it "doesn't fetch fancy_name" do
      expect {
        users[0].fancy_name
      }.to raise_error(ComputedModel::NotLoaded, "the field fancy_name is not loaded")
    end
  end

  context "when fetched with fancy_name" do
    let(:users) { self.class::Sandbox::User.list([1, 2, 3, 4], with: [:fancy_name]) }
    it "fetches raw_user.name" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.raw_user.name}).to contain_exactly("User One", "User Two", "User Four")
    end

    it "fetches name" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.name}).to contain_exactly("User One", "User Two", "User Four")
    end

    it "fetches fancy_name" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.fancy_name}).to contain_exactly("User One-san", "User Two-san", "User Four-san")
    end
  end
end
