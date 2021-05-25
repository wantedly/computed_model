# v0.3.0 migration guide

computed_model 0.3.0 comes with a number of breaking changes.
This guide will help you upgrade the library,
but please test your program before deploying to production.

## Major breaking: `ComputedModel` is now `ComputedModel::Model`

https://github.com/wantedly/computed_model/pull/17

Before:

```ruby
class User
  include ComputedModel
end
```

After:

```ruby
class User
  include ComputedModel::Model
end
```


## Major breaking: Indirect dependencies are now rejected

computed_model 0.3 checks if the requested field is a direct dependency.
If not, it raises `ComputedModel::ForbiddenDependency`.

https://github.com/wantedly/computed_model/pull/23

### Case 1

This will mostly affect the following "indirect dependency" case:

Before:

```ruby
class User
  dependency :bar
  computed def foo
    baz  # Accepted in computed_model 0.2
    # ...
  end

  dependency :baz
  computed def bar
    # ...
  end
end
```

After:

```ruby
class User
  dependency :bar, :baz  # Specify dependencies correctly
  computed def foo
    baz
    # ...
  end

  dependency :baz
  computed def bar
    # ...
  end
end
```

### Case 2

Before:

```ruby
class User
  dependency :bar
  computed def foo
    # ...
  end
end

users = User.bulk_load_and_compute([:foo], ...)
users[0].bar  # Accepted in computed_model 0.2
```

After:

```ruby
class User
  dependency :bar
  computed def foo
    # ...
  end
end

users = User.bulk_load_and_compute([:foo, :bar], ...)  # Specify dependencies correctly
users[0].bar
```

### Other cases

Previously, it sometimes happens to work depending on the order in which fields are loaded.

```ruby
class User
  # No dependency between foo and bar

  dependency :raw_user
  computed def foo
    # ...
  end

  dependency :raw_user
  computed def bar
    foo
    # ...
  end
end
```

It was already fragile in computed_model 0.2.
However, in computed_model 0.3,
it always leads to `ComputedModel::ForbiddenDependency`.


## Major breaking: `subdeps` are now called `subfields`

https://github.com/wantedly/computed_model/pull/31

Before:

```ruby
class User
  delegate_dependency :name, to: :raw_user, include_subdeps: true
end
```

After:

```ruby
class User
  delegate_dependency :name, to: :raw_user, include_subfields: true
end
```

We also recommend renaming block parameters named `subdeps` as `subfields`,
although not strictly necessary.


## Minor breaking: `computed_model_error` has been removed

It was useful in computed_model 0.1 but no longer needed in computed_model 0.2.

https://github.com/wantedly/computed_model/pull/18

```ruby
# No longer possible
self.computed_model_error = User::NotFound.new
```

## Minor breaking: Behavior of `dependency` not directly followed by `computed def` has been changed.

It doesn't effect you if all `dependency` declarations are followed by `computed def`.

```ruby
# Keeps working
dependency :foo
computed def bar
end
```

Otherwise `dependency` might be consumed by the next `define_loader` or `define_primary_loader`.

https://github.com/wantedly/computed_model/pull/20

Before:

```ruby
dependency :foo  # dependency of bar in computed_model 0.2

define_loader :quux, key: -> { id } do
  # ...
end

computed def bar
  # ...
end
```

After:

```ruby
# This would be interpreted as a dependency of quux
# dependency :foo

define_loader :quux, key: -> { id } do
  # ...
end

dependency :foo  # Place it here
computed def bar
  # ...
end
```

Additionally, `dependency` before `define_primary_loader` will be an error.

## Minor breaking: Cyclic dependency is an error even if it is unused

https://github.com/wantedly/computed_model/pull/24

Before:

```ruby
class User

  # Cyclic dependency is allowed as long as it's unused

  dependency :bar
  computed def foo
  end

  dependency :foo
  computed def bar
  end
end

users = User.bulk_load_and_compute([], ...)  # Neither :foo nor :bar is used
```

After:

```ruby
class User
  # Remove cyclic dependency altogether
end

users = User.bulk_load_and_compute([], ...)  # Neither :foo nor :bar is used
```

## Minor breaking: `nil`, `true`, `false` and `Proc` in subdeps are treated differently

They now have special meaning, so you should avoid using them as a normal subdependency.

https://github.com/wantedly/computed_model/pull/25

### `nil` and `false`

They are constantly false condition in conditional dependency. Unless otherwise enabled, the dependency won't be used.

Before:

```ruby
dependency foo: [nil, false]  # foo will be used
computed def bar
end
```

After:

```ruby
# dependency foo: [nil, false]  # foo won't be used
dependency foo: [:nil, :false]  # Use other values instead
computed def bar
end
```

### `true`

They are constantly true condition in conditional dependency. It's filtered out before passed to a loader or a primary loader.

Before:

```ruby
dependency foo: [true]  # true is given to "define_loader :foo do ... end"
computed def bar
end
```

After:

```ruby
# dependency foo: [true]  # true is ignored
dependency foo: [:true]  # Use other values instead
computed def bar
end
```

### Proc

Callable objects (objects implementing `#call`), including instances of `Proc`, is interpreted as a dynamic dependency.

Before:

```ruby
dependency foo: -> { raise "foo" }  # Passed to foo as-is
computed def bar
end
```

After:

```ruby
# dependency foo: -> { raise "foo" }  # Dynamic dependency. Called during dependency resolution.
dependency foo: { callback: -> { raise "foo" } }  # Wrap it in something
computed def bar
end
```


## Behavioral change: The order in which fields are loaded is changed

https://github.com/wantedly/computed_model/pull/24

Independent fields may be loaded in an arbitrary order. But implementation-wise, this is to some degree predictable.

computed_model 0.3 uses different dependency resolution algorithm and may produce different orders.
As a result, if your model is accidentally order-dependent, it may break with computed_model 0.3.


## Behavioral change: `ComputedModel::Model` now uses `ActiveSupport::Concern`

It won't affect you if you simply did `include ComputedModel::Model` (previously `include ComputedModel`) and nothing more.
Be cautious if you have a more complex inheritance/inclusion graph than that.


## Recommendation: `#verify_dependencies`

`#verify_dependencies` allows you to check the graph in the initialization process, rather than just before loading records.
We recommend doing this at the end of the class definition.

```ruby
class User
  define_loader ...

  computed def ... end

  verify_dependencies  # HERE
end
```
