## Unreleased

computed_model 0.3 comes with a great number of improvements, and a bunch of breaking changes.

- Breaking changes
  - `include ComputedModel` is now `include ComputedModel::Model`.
  - Indirect dependencies are now rejected.
  - `computed_model_error` was removed.
  - `dependency` before `define_loader` will be consumed and ignored.
  - `dependency` before `define_primary_loader` will be an error.
  - Cyclic dependency is an error even if it is unused.
  - `nil`, `true`, and `false` in subdeps will be filtered out before passed to a loader.
  - `ComputedModel.normalized_dependencies` now returns `[true]` instead of `[]` as an empty value.
- Notable behavioral changes
  - The order in which fields are loaded is changed.
  - `ComputedModel::Model` now uses `ActiveSupport::Concern`.
- Changed
  - Separate `ComputedModel::Model` from `ComputedModel` https://github.com/wantedly/computed_model/pull/17
  - Remove `computed_model_error` https://github.com/wantedly/computed_model/pull/18
  - Improve behavior around dependency-field pairing https://github.com/wantedly/computed_model/pull/20
  - Implement strict field access https://github.com/wantedly/computed_model/pull/23
  - Preprocess graph with topological sorting https://github.com/wantedly/computed_model/pull/24
  - Implement conditional dependencies and subdependency mapping/passthrough https://github.com/wantedly/computed_model/pull/25
  - Use `ActiveSupport::Concern` https://github.com/wantedly/computed_model/pull/26
- Added
  - `ComputedModel::Model#verify_dependencies`
  - Loader dependency https://github.com/wantedly/computed_model/pull/28
  - Support computed model inheritance https://github.com/wantedly/computed_model/pull/29
- Refactored
  - Extract `DepGraph` from `Model` https://github.com/wantedly/computed_model/pull/19
  - Define loader as a singleton method https://github.com/wantedly/computed_model/pull/21
  - Refactor `ComputedModel::Plan` https://github.com/wantedly/computed_model/pull/22
- Misc
  - Collect coverage https://github.com/wantedly/computed_model/pull/12 https://github.com/wantedly/computed_model/pull/16
  - Refactor tests https://github.com/wantedly/computed_model/pull/10 https://github.com/wantedly/computed_model/pull/15
  - Add tests https://github.com/wantedly/computed_model/pull/27

See [Migration-0.3.md](Migration-0.3.md) for migration.

### New feature: dynamic dependencies

Previously, subdeps are only useful for loaded fields and primary fields. Now computed fields can make use of subdeps!

```ruby
class User
  # Delegate subdeps
  dependency(
    blog_articles: -> (subdeps) { subdeps }
  )
  computed def filtered_blog_articles
    if current_subdeps.normalized[:image].any?
      # ...
    end
    # ...
  end
end
```

See [CONCEPTS.md](CONCEPTS.md) for more usages.

### New feature: loader dependency

You can specify dependency from a loaded field.

```ruby
class User
  dependency :raw_user  # dependency of :raw_books
  define_loader :raw_books, key: -> { id } do |subdeps, **|
    # ...
  end
end
```

### New feature: computed model inheritance

Now you can reuse computed model definitions via inheritance.

```ruby
module UserLikeConcern
  extends ActiveSupport::Concern
  include ComputedModel::Model

  dependency :preference, :profile
  computed def display_name
    "#{preference.title} #{profile.name}"
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

## 0.2.2

- [#7](https://github.com/wantedly/computed_model/pull/7) Accept Hash as a `with` parameter

## 0.2.1

- Fix problem with `prefix` option in `delegate_dependency` not working

## 0.2.0

- **BREAKING CHANGE** Make define_loader more concise interface like GraphQL's DataLoader.
- Introduce primary loader through `#define_primary_loader`.
- **BREAKING CHANGE** Change `#bulk_load_and_compute` signature to support primary loader.

## 0.1.1

- Expand docs.
- Add `ComputedModel#computed_model_error` for load cancellation

## 0.1.0

Initial release.
