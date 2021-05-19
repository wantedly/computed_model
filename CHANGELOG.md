## Unreleased

- Breaking changes
  - `include ComputedModel` is now `include ComputedModel::Model`.
  - Indirect dependencies are now rejected.
  - `computed_model_error` was removed.
  - `dependency` before `define_loader` will be consumed and ignored.
  - `dependency` before `define_primary_loader` will be an error.
  - Cyclic dependency is an error even if it is unused.
- Notable behavioral changes
  - The order in which fields are loaded is changed.
- Changed
  - Separate `ComputedModel::Model` from `ComputedModel` https://github.com/wantedly/computed_model/pull/17
  - Remove `computed_model_error` https://github.com/wantedly/computed_model/pull/18
  - Improve behavior around dependency-field pairing https://github.com/wantedly/computed_model/pull/20
  - Implement strict field access https://github.com/wantedly/computed_model/pull/23
  - Preprocess graph with topological sorting https://github.com/wantedly/computed_model/pull/24
- Added
  - `ComputedModel::Model#verify_dependencies`
- Refactored
  - Extract `DepGraph` from `Model` https://github.com/wantedly/computed_model/pull/19
  - Define loader as a singleton method https://github.com/wantedly/computed_model/pull/21
  - Refactor `ComputedModel::Plan` https://github.com/wantedly/computed_model/pull/22
- Misc
  - Collect coverage https://github.com/wantedly/computed_model/pull/12 https://github.com/wantedly/computed_model/pull/16
  - Refactor tests https://github.com/wantedly/computed_model/pull/10 https://github.com/wantedly/computed_model/pull/15


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
