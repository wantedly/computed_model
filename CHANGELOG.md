## Unreleased

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
