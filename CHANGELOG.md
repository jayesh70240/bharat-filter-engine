
```markdown
# Changelog

All notable changes to this project will be documented here.

## [0.1.1] - 2026-08-19

### Fixed

- `spec/engine_spec.rb`: the top-level `client`/`lead`/`sale` fixtures
  were declared with `let!`, which forced them to be created before
  *every* example in the file -- including the many examples further
  down that build their own local `sale`/`sale_one`/`sale_two`
  records. That stray fixture record (`stage: "qualified",
  approval_status: "approved", active: true, amount: 500`) then
  satisfied several unrelated examples' filters and leaked into their
  `contain_exactly(...)` results. Switched to lazy `let` so the
  fixture is only created by the handful of examples that actually
  reference it by name.
- `SearchBuilder#field_based_search` no longer silently ignores an
  `AND` group whose field isn't in `allowed_columns`. Previously the
  whole condition was dropped and every record was returned; now that
  group is correctly treated as unmatchable and the search returns no
  records.
- Test suite: several specs under `spec/engine_spec.rb` and
  `spec/rule_normalizer_spec.rb` called `described_class.apply`/
  `described_class.new(scope: ..., allowed_columns: ...)` while
  `described_class` resolved to the wrong class (`Engine` /
  `RuleNormalizer`), so those examples raised `NoMethodError` /
  `ArgumentError` instead of testing anything. They've been moved to
  their correct spec files (`search_builder_spec.rb`,
  `dynamic_filter_values_spec.rb`, `engine_spec.rb`) and now exercise
  the intended class.

### Changed

- `Engine`: extracted the repeated table-qualified `where` branching
  from the array/boolean/string/exact-numeric filters into a single
  `apply_condition` helper.
- `DynamicFilterValues` and `SearchBuilder` now reuse a single
  `AssociationResolver` instance instead of instantiating a new one
  per call/scope.

## [0.1.0] - 2026-08-19

### Added

- Initial Bharat Filter Engine implementation.
- String filters.
- Array filters.
- Boolean filters.
- Integer filters.
- Float filters.
- Numeric range filters.
- Date range filters.
- Nested association filters.
- Multi-level nested search.
- AND / OR search.
- Dynamic filter values.
- Legacy filter configuration support.
```
