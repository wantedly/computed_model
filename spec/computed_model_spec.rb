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

    class Book
      attr_accessor :id
      attr_accessor :author_id
      attr_accessor :title

      def initialize(id:, author_id:, title:)
        @id = id
        @author_id = author_id
        @title = title
      end

      def self.list(user_ids:)
        id_set = user_ids.to_set
        BOOKS.select { |b| id_set.include? b.author_id }
      end

      BOOKS = [
        Book.new(id: 1, author_id: 2, title: 'Bool One'),
        Book.new(id: 2, author_id: 4, title: 'Bool Two'),
        Book.new(id: 3, author_id: 2, title: 'Bool Three'),
        Book.new(id: 4, author_id: 2, title: 'Bool Four'),
      ].freeze
    end

    class User
      include ComputedModel

      attr_reader :id

      def initialize(raw_user)
        @id = raw_user.id
        @raw_user = raw_user
      end

      def self.list(ids, with:)
        bulk_list_and_compute(Array(with) + [:raw_user], ids: ids)
      end

      define_primary_loader :raw_user do |_subdeps, ids:, **_options|
        RawUser.list(ids).map { |raw_user| User.new(raw_user) }
      end

      define_loader :books, key: -> { id } do |keys, _subdeps|
        books = Book.list(user_ids: keys).group_by(&:author_id)
        keys.map { |key| books[key] || [] }
      end

      delegate_dependency :name, to: :raw_user

      dependency :name
      computed def fancy_name
        "#{name}-san"
      end

      dependency :books
      computed def book_count
        books.size
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

  context "when fetched with book_count" do
    let(:users) { self.class::Sandbox::User.list([1, 2, 3, 4], with: [:book_count]) }

    it "fetches book_count" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.book_count }).to contain_exactly(0, 3, 1)
    end
  end
end
