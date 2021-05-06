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

  let!(:raw_book1) { create(:raw_book, author_id: raw_user2.id, title: "Book One",   published_at: Date.new(2020,  4, 20)) }
  let!(:raw_book2) { create(:raw_book, author_id: raw_user4.id, title: "Book Two",   published_at: Date.new(2020,  7,  9)) }
  let!(:raw_book3) { create(:raw_book, author_id: raw_user2.id, title: "Book Three", published_at: Date.new(2020, 10,  1)) }
  let!(:raw_book4) { create(:raw_book, author_id: raw_user2.id, title: "Book Four",  published_at: Date.new(2021,  2, 13)) }
  let!(:raw_book5) { create(:raw_book, author_id: raw_user2.id, title: "Book Five",  published_at: nil) }

  class self::Sandbox
    class User
      include ComputedModel

      attr_reader :id

      def initialize(raw_user)
        @id = raw_user.id
        @raw_user = raw_user
      end

      def self.list(ids, with:)
        bulk_load_and_compute(with, ids: ids)
      end

      define_primary_loader :raw_user do |_subdeps, ids:, **_options|
        RawUser.where(id: ids).map { |raw_user| User.new(raw_user) }
      end

      define_loader :books_with_unpublished, key: -> { id } do |keys, subdeps|
        Book.list(user_ids: keys, with: subdeps).group_by(&:author_id)
      end

      delegate_dependency :name, to: :raw_user

      dependency books_with_unpublished: [:published]
      computed def books
        books_with_unpublished.select(&:published)
      end

      dependency :name
      computed def fancy_name
        "#{name}-san"
      end

      dependency :books
      computed def book_count
        (books || []).size
      end
    end

    class Book
      include ComputedModel

      attr_reader :id, :author_id

      def initialize(raw_book)
        @id = raw_book.id
        @author_id = raw_book.author_id
        @raw_book = raw_book
      end

      def self.list(user_ids:, with:)
        bulk_load_and_compute(with, user_ids: user_ids)
      end

      define_primary_loader :raw_book do |subdeps, user_ids:, **_options|
        RawBook.where(author_id: user_ids).select(:id, *subdeps).map { |raw_book| Book.new(raw_book) }
      end

      delegate_dependency :title, to: :raw_book, include_subdeps: true

      dependency raw_book: [:published_at]
      computed def published
        !!raw_book.published_at
      end
    end
  end

  context "when fetched with raw_user" do
    let(:users) { self.class::Sandbox::User.list(raw_user_ids, with: [:raw_user]) }
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
    let(:users) { self.class::Sandbox::User.list(raw_user_ids, with: [:name]) }
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
    let(:users) { self.class::Sandbox::User.list(raw_user_ids, with: [:fancy_name]) }
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
    let(:users) { self.class::Sandbox::User.list(raw_user_ids, with: [:book_count]) }

    it "fetches book_count" do
      expect(users.size).to eq(3)
      expect(users.map { |u| u.book_count }).to contain_exactly(0, 3, 1)
    end
  end

  context "when fetched with book.title" do
    let(:users) { self.class::Sandbox::User.list(raw_user_ids, with: { books: [:title]}) }

    it "fetches book_count" do
      expect(users.size).to eq(3)
      expect(users.map { |u| (u.books || []).map(&:title) }).to match([
        [],                                      # author_id: 1
        ['Book One', 'Book Three', 'Book Four'], # author_id: 2
        ['Book Two'],                            # author_id: 4
      ])
    end
  end
end
