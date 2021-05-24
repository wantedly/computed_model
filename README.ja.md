# ComputedModel

ComputedModelは依存解決アルゴリズムを備えた普遍的なバッチローダーです。

- 依存解決アルゴリズムの恩恵により、抽象化を損なわずに以下の3つを両立させることができます。
  - ActiveRecord等から読み込んだデータを加工して提供する。
  - ActiveRecord等からのデータの読み込みを一括で行うことでN+1問題を防ぐ。
  - 必要なデータだけを読み込む。
- 複数のデータソースからの読み込みにも対応。
- データソースに依存しない普遍的な設計。HTTPで取得した情報とActiveRecordから取得した情報の両方を使う、といったこともできます。

[English version](README.md)

## 解決したい問題

モデルが複雑化してくると、単にデータベースから取得した値を返すだけではなく、加工した値を返したくなることがあります。

```ruby
class User < ApplicationRecord
  has_one :preference
  has_one :profile

  def display_name
    "#{preference.title} #{profile.name}"
  end
end
```

ところがこれをそのまま使うと N+1 問題が発生することがあります。

```ruby
# N+1 問題!
User.where(id: friend_ids).map(&:display_name)
```

N+1問題を解決するには、 `#display_name` が何に依存していたかを調べ、それをpreloadしておく必要があります。

```ruby
User.where(id: friend_ids).preload(:preference, :profile).map(&:display_name)
#                                  ^^^^^^^^^^^^^^^^^^^^^ display_name の抽象化が漏れてしまう
```

これではせっかく `#display_name` を抽象化した意味が半減してしまいます。

ComputedModelは依存解決アルゴリズムをバッチローダーに接続することでこの問題を解消します。

```ruby
class User
  define_primary_loader :raw_user do ... end
  define_loader :preference do ... end
  define_loader :profile do ... end

  dependency :preference, :profile
  computed def display_name
    "#{preference.title} #{profile.name}"
  end
end
```

## インストール

Gemfileに以下の行を追加:

```ruby
gem 'computed_model', '~> 0.2.2'
```

その後、以下を実行:

    $ bundle

または直接インストール:

    $ gem install computed_model

## 動かせるサンプルコード

```ruby
require 'computed_model'

# この2つを外部から取得したデータとみなす (ActiveRecordやHTTPで取得したリソース)
RawUser = Struct.new(:id, :name, :title)
Preference = Struct.new(:user_id, :name_public)

class User
  include ComputedModel::Model

  attr_reader :id
  def initialize(raw_user)
    @id = raw_user.id
    @raw_user = raw_user
  end

  def self.list(ids, with:)
    bulk_load_and_compute(Array(with), ids: ids)
  end

  define_primary_loader :raw_user do |_subdeps, ids:, **|
    # ActiveRecordの場合:
    # raw_users = RawUser.where(id: ids).to_a
    raw_users = [
      RawUser.new(1, "Tanaka Taro", "Mr. "),
      RawUser.new(2, "Yamada Hanako", "Dr. "),
    ].filter { |u| ids.include?(u.id) }
    raw_users.map { |u| User.new(u) }
  end

  define_loader :preference, key: -> { id } do |user_ids, _subdeps, **|
    # ActiveRecordの場合:
    # Preference.where(user_id: user_ids).index_by(&:user_id)
    {
      1 => Preference.new(1, true),
      2 => Preference.new(2, false),
    }.filter { |k, _v| user_ids.include?(k) }
  end

  delegate_dependency :name, to: :raw_user
  delegate_dependency :title, to: :raw_user
  delegate_dependency :name_public, to: :preference

  dependency :name, :name_public
  computed def public_name
    name_public ? name : "Anonymous"
  end

  dependency :public_name, :title
  computed def public_name_with_title
    "#{title}#{public_name}"
  end
end

# あらかじめ要求したフィールドにだけアクセス可能
users = User.list([1, 2], with: [:public_name_with_title])
users.map(&:public_name_with_title) # => ["Mr. Tanaka Taro", "Dr. Anonymous"]
users.map(&:public_name) # => error (ForbiddenDependency)

users = User.list([1, 2], with: [:public_name_with_title, :public_name])
users.map(&:public_name_with_title) # => ["Mr. Tanaka Taro", "Dr. Anonymous"]
users.map(&:public_name) # => ["Tanaka Taro", "Anonymous"]

# 次のような場合は preference は読み込まれない。
users = User.list([1, 2], with: [:title])
users.map(&:title) # => ["Mr. ", "Dr. "]
```

