
```markdown
# Changelog

All notable changes to this project will be documented here.

## [0.2.0] - 2026-11-09

### Added

- Added `:presence` filter type to filter records by presence or blankness
- Added `:between` range type for `:integer` and `:float` filters, accepting hashes (`from`/`to`), arrays, or comma-separated bounds
- Added `negate: true` rule configuration for `:string`, `:boolean`, `:array`, and exact numeric filters
- Added `filter_term` and `filter_limit` parameter support to `Engine.filter_values` and `DynamicFilterValues`
- Added strict configuration validation via `RuleNormalizer`, raising `InvalidConfigurationError` on invalid types, missing keys, or unsupported option combinations
- Added `InvalidAssociationError` when a configured nested association cannot be resolved on the model
- Added subquery resolution via `JoinTracker` for nested associations that would otherwise create conflicting table joins

### Changed

- Escaped SQL `LIKE` wildcards (`%`, `_`, `\`) in search queries and dynamic filter value terms
- Replaced PostgreSQL-specific `::text` casting with standard `CAST(... AS TEXT)` for `id` search queries
- Enforced that field-based search expressions only query columns defined in `allowed_columns`

### Fixed

- Fixed dynamic filter value retrieval on non-string columns to prevent querying for empty strings
- Fixed nested column resolution to verify that the target column actually exists on the associated model



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
