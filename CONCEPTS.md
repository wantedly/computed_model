# Basic concepts and features

[日本語版](CONCEPTS.ja.md)

## Wrapping classes

We don't (yet) support directly including `ComputedModel::Model` into ActiveRecord classes or similar ones.
In that case, we recommend creating a wrapper class and reference the original class via the primary loader
(described later).

## Fields

**Field** are certain attributes managed by ComputedModel. It's a unit of dependency resolution and
there are three kinds of fields:

- computed fields
- loaded fields
- primary fields

### computed fields

A computed field is a field in which it's value is derived from other fields.
It's calculated independently per record.

```ruby
class User
  dependency :preference, :profile
  computed def display_name
    "#{preference.title} #{profile.name}"
  end
end
```

### loaded fields

A loaded field is a field in which we obtain values in batches.

```ruby
class User
  define_loader :preference, key: -> { id } do |ids, _subfields, **|
    Preference.where(user_id: ids).index_by(&:user_id)
  end
end
```

### primary fields

A primary field is responsible in searching/enumerating the whole records,
in addition to the usual responsibility of loaded fields.

Consider a hypothetical `User` class for example. In this case you might want to inquiry somewhere (a data source)
whether a user with a certain id exists.

If it were a hypothetical ActiveRecord class `RawUser`, the primary field would be defined as follows:

```ruby
class User
  def initialize(raw_user)
    @raw_user = raw_user
  end

  define_primary_loader :raw_user do |_subfields, ids:, **|
    # You need to set @raw_user in User#initialize.
    RawUser.where(id: ids).map { |u| User.new(u) }
  end
end
```

## When computation is done

All necessary fields are computed eagerly when ComputedModel's `bulk_load_and_compute` is called.

It doesn't (yet) provide lazy loading functionality.

## Dependency

You can declare dependencies on a field.
As an exception, the primary field cannot have a dependency (but it can have dependents, of course).

```ruby
class User
  dependency :preference, :profile
  computed def display_name
    "#{preference.title} #{profile.name}"
  end
end
```

In `computed def` or `define_loader`, among all fields, you can only read values of explicitly declared dependencies.
You cannot read other fields even if it happens to be present (such as indirect dependencies).

## `bulk_load_and_compute`

`bulk_load_and_compute` is the very method you need to load ComputedModel records.
We recommend wrapping the method in each model class.
This is mostly because there is a lot of freedom in the format of the batch-loading parameters (described later)
and it will likely cause mistakes if used directly.

```ruby
class User
  # You can specify an array of fields like [:display_name, :title] in the `with` parameter.
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

There is no such method as load a single record. You can easily implement it by wrapping `bulk_load_and_compute`.
If you want a certain optimization for single-record cases, you may want to write conditionals in `define_loader` or `define_primary_loader`.

## Subfield selectors

Subfield selectors (or subdependencies) are additional information attached to a dependency.

Implementation-wise they're just arbitrary messages sent from a field to its dependency.
Nonetheless we expect them to be used to request "subfields" as the name suggests.

```ruby
class User
  define_loader :profile, key: -> { id } do |ids, subfields, **|
    Profile.preload(subfields).where(user_id: ids).index_by(&:user_id)
  end

  # [:contact_phones] will be passed to the loader of `profile`.
  dependency profile: :contact_phones
  computed def contact_phones
    profile.contact_phones
  end
end
```

You can also receive subfield selectors in a computed field. See the "Dynamic dependencies" section later.

## Batch-loading parameters

The keyword parameters given to `bulk_load_and_compute` is passed through to the blocks of `define_primary_loader` or `define_loader`.
You can use it for various purposes, some of which we present below:

### Searching records by conditions other than id

You can pass multiple different search conditions through the keyword parameters.

```ruby
class User
  def self.list(ids, with:)
    bulk_load_and_compute(with, ids: ids, emails: nil)
  end

  def self.list_by_emails(emails, with:)
    bulk_load_and_compute(with, ids: nil, emails: emails)
  end

  define_primary_loader :raw_user do |_subfields, ids:, emails:, **|
    s = User.all
    s = s.where(id: ids) if ids
    s = s.where(email: emails) if emails
    s.map { |u| User.new(u) }
  end
end
```

### Current user

Consider a situation where we want to present different information depending on whom the user is logging in as.
You can implement it by including the current user in the keyword parameters.

```ruby
class User
  def initialize(raw_user, current_user_id)
    @raw_user = raw_user
    @current_user_id = current_user_id
  end

  define_primary_loader :raw_user do |_subfields, current_user_id:, ids:, **|
    # ...
  end

  define_loader :profile, key: -> { id } do |ids, _subfields, current_user_id:, **|
    # ...
  end
end
```

## Dynamic dependencies

You can configure dynamic dependencies by specifying Procs as subfield selectors.

### Conditional dependencies

Dependencies which are conditionally enabled based on incoming subfield selectors:

```ruby

class User
  dependency(
    :blog_articles,
    # Load image_permissions only when it receives `image` subfield selector.
    image_permissions: -> (subfields) { subfields.normalized[:image].any? }
  )
  computed def filtered_blog_articles
    if current_subfields.normalized[:image].any?
      # ...
    end
    # ...
  end
end
```

### Subfield selectors passthrough

Passing through incoming subfield selectors to another field:

```ruby

class User
  dependency(
    blog_articles: -> (subfields) { subfields }
  )
  computed def filtered_blog_articles
    if current_subfields.normalized[:image].any?
      # ...
    end
    # ...
  end
end
```

### Subfield selectors mapping

Processing incoming subfield selectors and pass the result as outgoing subfield selectors to another field:

```ruby
class User
  dependency(
    # Always load blog_articles, but
    # if the incoming subfield selectors contain `blog_articles`, pass them down to the dependency.
    blog_articles: [true, -> (subfields) { subfields.normalized[:blog_articles] }],
    # Always load wiki_articles, but
    # if the incoming subfield selectors contain `wiki_articles`, pass them down to the dependency.
    wiki_articles: [true, -> (subfields) { subfields.normalized[:wiki_articles] }]
  )
  computed def articles
    (blog_articles + wiki_articles).sort_by { |article| article.created_at }.reverse
  end
end
```

### Detailed dependency format

You can pass 0 or more arguments to `dependency`.
They're pushed into an internal array and will be consumed by the next `computed def` or `define_loader`.
So they have the same meaning:

```ruby
dependency :profile
dependency :preference
computed def display_name; ...; end
```

```ruby
dependency :profile, :preference
computed def display_name; ...; end
```

The resulting array will be normalized as a hash by `ComputedModel.normalize_dependencies`. The rules are:

- If it's a Symbol, convert it to a singleton hash containing the key. (`:foo` → `{ foo: [true] }`)
- If it's a Hash, convert the values as follows:
  - If the value is an empty array, replace it with `[true]`. (`{ foo: [] }` → `{ foo: [true] }`)
  - If the value is not an array, convert it to the singleton array. (`{ foo: :bar }` → `{ foo: [:bar] }`)
  - If the value is a non-empty array, keep it as-is.
- If it's an Array, convert each element following the rules above and merge the keys of the hashes. Hash values are always arrays and will be simply concatenated.
  - `[:foo, :bar]` → `{ foo: [true], bar: [true] }`
  - `[{ foo: :foo }, { foo: :bar }]` → `{ foo: [:foo, :bar] }`

We interpret the resulting hash as a dictionary from a field name (dependency names) and it's subfield selectors.

Each subfield selector is interpreted as below:

- If it contains `#call`able objects (such as Proc), call them with `subfields` (incoming subfield selectors) as their argument.
  - Expand the result if it's an Array. (`{ foo: [-> { [:bar, :baz] }] }` → `{ foo: [:bar, :baz] }`)
  - Otherwise push the result. (`{ foo: [-> { :bar }] }` → `{ foo: [:bar] }`)
- After Proc substitution, check if it contains any truthy value (value other than `nil` or `false`).
  - If no truthy value is found, we don't use the dependency as the condition is not met.
  - Otherwise (if truthy value is found), use the dependency. Subfield selectors (after substitution) are sent to the dependency as-is.

For that reason, in most cases subfield selectors contain `true`. As a special case we remove them in the following cases:

- We'll remove `nil`, `false`, `true` from the subfield selectors before passed to a `define_loader` or `define_primary_loader` block.
- In certain cases you can use `subfields.normalize` to get a hash from the subfield selectors array. This is basically `ComputedModel.normalize_dependencies` but `nil`, `false`, `true` will be removed as part of preprocessing.

## Inheritance

You can also define partial ComputedModel class/module. You can then inherit/include it in a different class and complete the definition.

```ruby
module UserLikeConcern
  extend ActiveSupport::Concern
  include ComputedModel::Model

  included do
    dependency :preference, :profile
    computed def display_name
      "#{preference.title} #{profile.name}"
    end
  end
end

class User
  include UserLikeConcern

  define_loader :preference, key: -> { id } do ... end
  define_loader :profile, key: -> { id } do ... end
end

class Admin
  include UserLikeConcern

  define_loader :preference, key: -> { id } do ... end
  define_loader :profile, key: -> { id } do ... end
end
```

Note that in certain cases overriding might work incorrectly (because `computed def` internally renames the given method)
