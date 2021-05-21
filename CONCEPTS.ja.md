# 基本概念と機能

## ラッパークラス

ComputedModelは、ActiveRecordクラスなどに直接includeして使うことを(今のところ)想定していません。
その場合ラッパークラスを作成し、元のクラスのオブジェクトは主ローダー (後述) として定義するのがよいでしょう。

## フィールド

**フィールド**はComputedModelの管理下にある属性のことで、依存管理の基本単位です。以下の3種類のフィールドがあります。

- computed field (計算フィールド)
- loaded field (読み込みフィールド)
- primary field (主フィールド)

### computed field (計算フィールド)

別のフィールドの組み合わせで算出されるフィールドです。各レコードごとに独立に計算されます。

```ruby
class User
  dependency :preference, :profile
  computed def display_name
    "#{preference.title} #{profile.name}"
  end
end
```

### loaded field (読み込みフィールド)

複数レコードに対してまとめて読み込むフィールドです。

```ruby
class User
  define_loader :preference, key: -> { id } do |ids, _subdeps, **|
    Preference.where(user_id: ids).index_by(&:user_id)
  end
end
```

### primary field (主フィールド)

loaded fieldの機能に加えて、レコードの検索・列挙機能を担う特別なフィールドです。

たとえば `User` の場合、あるidのユーザーが存在するかどうかはどこかのデータソースに問い合わせる必要があるはずです。
それがたとえばActiveRecordの `RawUser` クラスである場合、主フィールドは以下のように定義されます。

```ruby
class User
  def initialize(raw_user)
    @raw_user = raw_user
  end

  define_primary_loader :raw_user do |_subdeps, ids:, **|
    # User#initialize 内で @raw_user をセットする必要がある
    RawUser.where(id: ids).map { |u| User.new(u) }
  end
end
```

## 計算タイミング

ComputedModelの `bulk_load_and_compute` が呼ばれたタイミングで全ての必要なフィールドが計算されます。

遅延ロードは今のところサポートしていません。

## 依存関係

フィールドには依存関係を宣言することができます。
ただし、主フィールドは依存関係を持つことができません。 (他のフィールドから主フィールドに依存することはできます。)

```ruby
class User
  dependency :preference, :profile
  computed def display_name
    "#{preference.title} #{profile.name}"
  end
end
```

`computed def` 内や `define_loader` のブロック内では、 `dependency` で宣言したフィールドのみ参照できます。
間接依存しているフィールドなど、たまたまロードされている場合でもアクセスはブロックされます。

## `bulk_load_and_compute`

ComputedModelの読み込みを行うメソッドが `bulk_load_and_compute` です。
`bulk_load_and_compute` をそのまま使うのではなく、各モデルでラッパー関数を実装することが推奨されます。
(これは後述するバッチロード引数の自由度が高く、そのままでは使い間違いが起きやすいからです)

```ruby
class User
  # with には [:display_name, :title] のようにフィールド名の配列を指定する
  def self.list(ids, with:)
    bulk_load_and_compute(with, ids: ids)
  end

  def self.get(id, with:)
    list([id], with: with).first
  end

  def self.get!(id, with:)
    get(id, with: with) || (raise User::NotFound)
  end
end
```

単独のレコードを読み込むための専用のメソッドはありません。こちらも `bulk_load_and_compute` のラッパーを実装することで実現してください。
もし単独のレコードであることを利用した最適化が必要な場合は、 `define_loader` や `define_primary_loader` で分岐を実装するとよいでしょう。

## 下位フィールドセレクタ

下位フィールドセレクタ (subfield selector) または 下位依存 (subdependency) は依存関係につけられる追加の情報です。

実装上はフィールドから依存先フィールドに任意のメッセージを送ることができる仕組みになっていますが、
名前の通りフィールドにぶら下がっている情報の取得に使うことを想定しています。

```ruby
class User
  define_loader :profile, key: -> { id } do |ids, subdeps, **|
    Profile.preload(subdeps).where(user_id: ids).index_by(&:user_id)
  end

  # profileのローダーに [:contact_phones] が渡される
  dependency profile: :contact_phones
  computed def contact_phones
    profile.contact_phones
  end
end
```

計算フィールドでも下位フィールドセレクタを使うことができます。 (「高度な依存関係」で後述)

## バッチロード引数

`bulk_load_and_compute` のキーワード引数は、 `define_primary_loader` や `define_loader` のブロックにそのまま渡されます。
状況にあわせて色々な使い方が考えられます。

### id以外での検索

複数の検索条件を与えることもできます。

```ruby
class User
  def self.list(ids, with:)
    bulk_load_and_compute(with, ids: ids, emails: nil)
  end

  def self.list_by_emails(emails, with:)
    bulk_load_and_compute(with, ids: nil, emails: emails)
  end

  define_primary_loader :raw_user do |_subdeps, ids:, emails:, **|
    s = User.all
    s = s.where(id: ids) if ids
    s = s.where(email: emails) if emails
    s.map { |u| User.new(u) }
  end
end
```

### カレントユーザー

「今どのユーザーでログインしているか」によって情報の見え方が違う、というような状況を考えます。これはカレントユーザー情報をバッチロード引数に含めることで実現可能です。

```ruby
class User
  def initialize(raw_user, current_user_id)
    @raw_user = raw_user
    @current_user_id = current_user_id
  end

  define_primary_loader :raw_user do |_subdeps, current_user_id:, ids:, **|
    # ...
  end

  define_loader :profile, key: -> { id } do |ids, _subdeps, current_user_id:, **|
    # ...
  end
end
```

## 高度な依存関係

下位フィールドセレクタにprocを指定することで、より高度な制御をすることができます。

### 条件つき依存

受け取った下位フィールドセレクタの内容にもとづいて、条件つき依存関係を定義することができます。

```ruby
class User
  dependency(
    :blog_articles,
    value: -> (subdeps) { subdeps.normalized[:image].any? }
  )
  computed def filtered_blog_articles

  end
end
```
