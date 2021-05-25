# frozen_string_literal: true

require 'spec_helper'
require 'support/models/raw_user'
require 'support/models/raw_user_extra'
require 'support/models/raw_book'

RSpec.describe ComputedModel::Model do
  let!(:raw_user1) { create(:raw_user, name: 'User One') }
  let!(:raw_user2) { create(:raw_user, name: 'User Two') }
  let!(:raw_user_extra1) { create(:raw_user_extra, id: raw_user1.id, token: 'abcdef') }
  let(:raw_user_ids) { [raw_user1.id, raw_user2.id] }

  let(:user_class) do
    record_user_subfields = -> (subfields) { @user_subfields = subfields }
    record_user_extra_subfields = -> (subfields) { @user_extra_subfields = subfields }
    Class.new do
      def self.name; 'User'; end
      def self.to_s; 'User'; end

      include ComputedModel::Model

      attr_reader :id

      def initialize(raw_user)
        @id = raw_user.id
        @raw_user = raw_user
      end

      def self.list(ids, with:)
        bulk_load_and_compute(with, ids: ids)
      end

      define_primary_loader :raw_user do |subfields, ids:, **_options|
        record_user_subfields.call(subfields)
        RawUser.where(id: ids).map { |raw_user| self.new(raw_user) }
      end

      define_loader :raw_user_extra, key: -> { id } do |keys, subfields|
        record_user_extra_subfields.call(subfields)
        RawUserExtra.where(id: keys).index_by(&:id)
      end
    end
  end
  before { stub_const('User', user_class) }

  describe 'delegate_dependency' do
    describe 'default' do
      before do
        user_class.module_eval do
          delegate_dependency :name, to: :raw_user
        end
      end

      it 'delegates dependency' do
        u = User.list(raw_user_ids, with: [:name]).first
        expect(u.name).to eq('User One')
      end
    end

    describe 'with prefix' do
      before do
        user_class.module_eval do
          delegate_dependency :name, to: :raw_user, prefix: :user
        end
      end

      it 'generates a prefixed field' do
        u = User.list(raw_user_ids, with: [:user_name]).first
        expect(u.user_name).to eq('User One')
      end
    end

    describe 'without allow_nil' do
      before do
        user_class.module_eval do
          delegate_dependency :token, to: :raw_user_extra
        end
      end

      it 'fails on nil field' do
        expect {
          User.list(raw_user_ids, with: [:token])
        }.to raise_error(NoMethodError, "undefined method `token' for nil:NilClass")
      end
    end

    describe 'with allow_nil' do
      before do
        user_class.module_eval do
          delegate_dependency :token, allow_nil: true, to: :raw_user_extra
        end
      end

      it 'delegates dependency' do
        users = User.list(raw_user_ids, with: [:token])
        expect(users.map(&:token)).to eq(["abcdef", nil])
      end
    end

    describe 'without include_subfields' do
      before do
        user_class.module_eval do
          delegate_dependency :name, to: :raw_user
        end
      end

      it "doesn't generate subfields" do
        User.list(raw_user_ids, with: [:name])
        expect(@user_subfields).to eq([])
      end
    end

    describe 'without include_subfields' do
      before do
        user_class.module_eval do
          delegate_dependency :name, to: :raw_user, include_subfields: true
        end
      end

      it 'generates subfields' do
        User.list(raw_user_ids, with: [:name])
        expect(@user_subfields).to eq([:name])
      end
    end
  end
end
