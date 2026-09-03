# 🇮🇳 Bharat Filter Engine

A generic, configuration-driven filtering engine for Ruby on Rails
`ActiveRecord` applications. Instead of hand-rolling `where` clauses
for every index action, you declare a **filter config** once and let
the engine turn incoming params (from a form, an API request, a
query string) into a filtered `ActiveRecord::Relation` — including
filters on associated models, free-text search, and dynamically
populated dropdown values.

[![Gem Version](https://img.shields.io/badge/version-0.1.2-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Table of contents

- [Features](#features)
- [Installation](#installation)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Filter config reference](#filter-config-reference)
- [Filter types with examples](#filter-types-with-examples)
  - [string](#string)
  - [array](#array)
  - [boolean](#boolean)
  - [integer / float](#integer--float)
  - [daterange](#daterange)
  - [search](#search)
- [Nested / association filters](#nested--association-filters)
- [Free-text search (`search` filter type)](#free-text-search-search-filter-type)
- [Dynamic filter values (for dropdowns)](#dynamic-filter-values-for-dropdowns)
- [Full Rails controller example](#full-rails-controller-example)
- [Legacy config format](#legacy-config-format)
- [Error handling](#error-handling)
- [Running the test suite](#running-the-test-suite)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- String, array (multi-select), boolean, integer, and float filters
- Greater-than-or-equal / less-than-or-equal numeric range filters
- Date range filters (hash, array, or comma-separated string input)
- Nested / multi-level association filters (`lead__client__name`)
- Free-text search across multiple columns, including associations
- `field=value` search syntax with `&` (AND) / `|` (OR) grouping
- Dynamic filter values (distinct column values, e.g. to populate a
  dropdown) for both direct and nested/associated columns
- Automatically ignores blank params so existing scope chains and
  default ordering are left untouched
- Legacy config format still supported (see below)

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem "bharat_filter_engine"
```

And then run:

```bash
bundle install
```

Or install it yourself:

```bash
gem install bharat_filter_engine
```

**Requirements:** Ruby >= 3.0, ActiveRecord/ActiveModel/ActiveSupport >= 6.1.

## Quick start

```ruby
# 1. Define a filter config for your model (usually a constant or a
#    method on the model/controller).
FILTER_CONFIG = {
  stage: {
    type: :single,
    filter_type: :string,
    dbcolumn: :stage
  },

  status: {
    type: :single,
    filter_type: :array,
    dbcolumn: :approval_status
  },

  amount: {
    type: :single,
    filter_type: :integer,
    dbcolumn: :amount,
    range_type: :gte
  }
}

# 2. Apply it to a scope using whatever params your app received.
result = BharatFilterEngine.apply(
  scope: Sale.all,
  config: FILTER_CONFIG,
  params: {
    stage: "qualified",
    status: ["approved", "pending"],
    amount: "500"
  }
)

result # => an ActiveRecord::Relation, filtered and ready to use
```

That's it — `result` behaves exactly like any other `ActiveRecord::Relation`,
so you can keep chaining `.order`, `.page`, `.includes`, etc.

## How it works

`BharatFilterEngine.apply` takes three keyword arguments:

| Argument | Type                        | Description                                                              |
|----------|-----------------------------|----------------------------------------------------------------------------|
| `scope`  | `ActiveRecord::Relation`    | The base scope to filter (e.g. `Sale.all`, `current_user.sales`).          |
| `config` | `Hash`                      | Maps a **param key** to a **filter rule** (see reference below).           |
| `params` | `Hash` / `ActionController::Parameters` | The incoming request params.                                 |

For every `key => rule` pair in `config`, the engine looks up
`params[key]`. If the value is blank (`nil`, `""`, `[]` — but **not**
`false`), that filter is skipped entirely, so unrelated scope
conditions and default ordering are preserved. Otherwise the rule is
applied to the scope.

Params are normalized automatically before filtering:

- Comma-separated strings become arrays: `"approved,pending"` → `["approved", "pending"]`
- JSON array strings are parsed: `'["approved","pending"]'` → `["approved", "pending"]`
- All keys are deep-symbolized, so both `"stage"` and `:stage` work.

## Filter config reference

Each entry in `config` is a hash describing one filter rule:

```ruby
{
  type:        :single | :nested,   # :single = direct column, :nested = via association
  filter_type: :string | :array | :boolean | :integer | :float | :daterange | :search,
  dbcolumn:    :column_name,        # the actual DB column (or one of the search columns)
  association: :lead,               # required when type: :nested — "__" separated for multi-level
  range_type:  :gte | :lte,         # optional, for :integer / :float
  dbcolumns:   [:stage, :"lead__source"] # required when filter_type: :search
}
```

## Filter types with examples

All examples below assume the schema used in the spec suite:

```ruby
Organization has_many :clients
Client       belongs_to :organization, has_many :leads
Lead         belongs_to :client,       has_many :sales
Sale         belongs_to :lead
```

### string

Exact match on a column.

```ruby
config = {
  stage: {
    type: :single,
    filter_type: :string,
    dbcolumn: :stage
  }
}

BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { stage: "qualified" }
)
# SQL: WHERE sales.stage = 'qualified'
```

### array

Matches any value in the given array (`IN`). Accepts an actual array,
a comma-separated string, or a JSON array string.

```ruby
config = {
  status: {
    type: :single,
    filter_type: :array,
    dbcolumn: :approval_status
  }
}

BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { status: ["approved", "pending"] }
)
# same as params: { status: "approved,pending" }
# same as params: { status: '["approved","pending"]' }
# SQL: WHERE sales.approval_status IN ('approved', 'pending')
```

### boolean

Casts common truthy/falsy input (`"true"`, `"1"`, `true`, `"false"`, `false`, etc.)
using `ActiveModel::Type::Boolean`.

```ruby
config = {
  active: {
    type: :single,
    filter_type: :boolean,
    dbcolumn: :active
  }
}

BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { active: "true" }
)
# SQL: WHERE sales.active = TRUE
```

> Note: `false` is a meaningful value and is **not** treated as blank,
> so `params: { active: false }` correctly filters for inactive
> records instead of being skipped.

### integer / float

Exact match by default. Add `range_type: :gte` or `range_type: :lte`
for open-ended range filters.

```ruby
# Exact match
config = {
  amount: {
    type: :single,
    filter_type: :integer,
    dbcolumn: :amount
  }
}

BharatFilterEngine.apply(scope: Sale.all, config: config, params: { amount: "500" })
# SQL: WHERE sales.amount = 500

# Greater-than-or-equal
config = {
  amount: {
    type: :single,
    filter_type: :integer,
    dbcolumn: :amount,
    range_type: :gte
  }
}

BharatFilterEngine.apply(scope: Sale.all, config: config, params: { amount: 400 })
# SQL: WHERE sales.amount >= 400

# Float, less-than-or-equal
config = {
  conversion_rate: {
    type: :single,
    filter_type: :float,
    dbcolumn: :conversion_rate,
    range_type: :lte
  }
}

BharatFilterEngine.apply(scope: Sale.all, config: config, params: { conversion_rate: "20.5" })
# SQL: WHERE sales.conversion_rate <= 20.5
```

### daterange

Accepts three input shapes for `from`/`to`. Either bound alone is
enough — leaving one out gives an open-ended range.

```ruby
config = {
  actual_sale_date: {
    type: :single,
    filter_type: :daterange,
    dbcolumn: :actual_sale_date
  }
}

# Hash form
BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { actual_sale_date: { from: "2026-07-01", to: "2026-07-31" } }
)

# Array form: [from, to]
BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { actual_sale_date: ["2026-07-01", "2026-07-31"] }
)

# Comma-separated string form
BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { actual_sale_date: "2026-07-01,2026-07-31" }
)

# Open-ended — only a lower bound
BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { actual_sale_date: { from: "2026-08-01" } }
)
# SQL: WHERE sales.actual_sale_date >= '2026-08-01 00:00:00'
```

Dates are parsed with `Date.parse` and expanded to
`beginning_of_day` (from) / `end_of_day` (to), so a plain `"2026-07-20"`
correctly captures every record on that calendar day.

### search

See the dedicated [Free-text search](#free-text-search-search-filter-type)
section below — it's the same filter type, just wired up through
`config` instead of used directly.

```ruby
config = {
  q: {
    type: :single,
    filter_type: :search,
    dbcolumns: [:stage, :approval_status, :"lead__source"]
  }
}

BharatFilterEngine.apply(scope: Sale.all, config: config, params: { q: "google" })
```

## Nested / association filters

Set `type: :nested` and `association:` to filter on a column that
belongs to an associated model. The engine resolves the association
via `ActiveRecord::Base.reflect_on_association`, joins it (with
`.distinct` applied automatically to avoid duplicate rows from the
join), and applies the same filter types described above.

```ruby
# Filter sales by their lead's source
config = {
  lead_source: {
    type: :nested,
    filter_type: :array,
    association: :lead,
    dbcolumn: :source
  }
}

BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { lead_source: ["google", "referral"] }
)
# SQL: ... INNER JOIN leads ON leads.id = sales.lead_id
#      WHERE leads.source IN ('google', 'referral')
```

### Multi-level associations

Use `__` (double underscore) to walk through more than one
association — this works both in `association:` for `:nested` filter
rules and directly in `dbcolumns:` for `search`.

```ruby
config = {
  organization_name: {
    type: :nested,
    filter_type: :string,
    association: :lead__client__organization,
    dbcolumn: :name
  }
}

BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { organization_name: "Acme" }
)
# Joins sales -> leads -> clients -> organizations
```

## Free-text search (`search` filter type)

The `search` filter type wires up `BharatFilterEngine::SearchBuilder`,
which supports two input styles:

**1. Simple search** — no `=` sign. Matches the query (case-insensitive,
substring) against *any* of the allowed columns, `OR`-ed together.

```ruby
config = {
  q: {
    type: :single,
    filter_type: :search,
    dbcolumns: [:stage, :"lead__source", :"lead__client__name"]
  }
}

BharatFilterEngine.apply(scope: Sale.all, config: config, params: { q: "goog" })
# matches any Sale whose stage, lead.source, or lead.client.name
# contains "goog" (case-insensitive)
```

**2. Field-based search** — contains `=`. Lets the caller target
specific fields, with `&` for AND and `|` for OR (within an AND
group). Only fields present in `dbcolumns:` are honored; anything
else makes that AND group unsatisfiable (so the search returns no
records rather than silently matching everything).

```ruby
BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { q: "stage=qualified&lead__source=google" }
)
# WHERE stage ILIKE '%qualified%' AND leads.source ILIKE '%google%'

BharatFilterEngine.apply(
  scope: Sale.all,
  config: config,
  params: { q: "stage=qualified&approval_status=approved|approval_status=pending" }
)
# WHERE stage ILIKE '%qualified%'
#   AND (approval_status ILIKE '%approved%' OR approval_status ILIKE '%pending%')
```

`id` gets special handling so you can search it as text
(`"id=42"` → `id::text ILIKE '%42%'`).

You can also use `SearchBuilder` directly, without going through a
full config/`BharatFilterEngine.apply` call:

```ruby
BharatFilterEngine::SearchBuilder.new(
  scope: Sale.all,
  allowed_columns: [:stage, :"lead__source"]
).apply("qualified")
```

## Dynamic filter values (for dropdowns)

Use `BharatFilterEngine.filter_values` to fetch the distinct,
non-blank values for a configured filter field — handy for populating
a `<select>`/dropdown/autocomplete without writing a separate query.

```ruby
BharatFilterEngine.filter_values(
  scope: Sale.all,
  config: FILTER_CONFIG,
  params: { filter_field: "stage" }
)
# => ["new", "qualified", ...]  (sorted, unique, blanks excluded)

# Works for nested/associated fields too, resolved from the same
# config entry's `association:` + `dbcolumn:`
BharatFilterEngine.filter_values(
  scope: Sale.all,
  config: FILTER_CONFIG,
  params: { filter_field: "lead_source" }
)
# => ["google", "referral", ...]
```

If `filter_field` isn't present in `config`, or doesn't have a
`dbcolumn`, this returns `[]` rather than raising.

You can also use `BharatFilterEngine::DynamicFilterValues` directly:

```ruby
BharatFilterEngine::DynamicFilterValues.new(
  scope: Sale.all,
  field: "lead__client__name"   # "__" notation, same as association filters
).call
# => ["Acme Client", "Beta Client", ...] or nil if the field is invalid
```

## Full Rails controller example

```ruby
class SalesController < ApplicationController
  FILTER_CONFIG = {
    stage: {
      type: :single,
      filter_type: :string,
      dbcolumn: :stage
    },

    status: {
      type: :single,
      filter_type: :array,
      dbcolumn: :approval_status
    },

    active: {
      type: :single,
      filter_type: :boolean,
      dbcolumn: :active
    },

    amount_from: {
      type: :single,
      filter_type: :integer,
      dbcolumn: :amount,
      range_type: :gte
    },

    sale_date: {
      type: :single,
      filter_type: :daterange,
      dbcolumn: :actual_sale_date
    },

    lead_source: {
      type: :nested,
      filter_type: :array,
      association: :lead,
      dbcolumn: :source
    },

    q: {
      type: :single,
      filter_type: :search,
      dbcolumns: [:stage, :"lead__source", :"lead__client__name"]
    }
  }.freeze

  def index
    @sales = BharatFilterEngine.apply(
      scope: current_organization.sales.order(created_at: :desc),
      config: FILTER_CONFIG,
      params: filter_params
    ).page(params[:page])
  end

  # For an AJAX-populated dropdown, e.g. GET /sales/filter_values?filter_field=stage
  def filter_values
    render json: BharatFilterEngine.filter_values(
      scope: current_organization.sales,
      config: FILTER_CONFIG,
      params: params
    )
  end

  private

  def filter_params
    params.permit(
      :stage, :active, :amount_from, :q,
      status: [], lead_source: [],
      sale_date: [:from, :to]
    )
  end
end
```

Because `BharatFilterEngine.apply` ignores blank params, this same
config works whether the user has applied zero, one, or every filter
— no conditional branching required in the controller.

## Legacy config format

Older/simpler config entries (`type:` doubling as the filter type,
without an explicit `filter_type:`) are automatically normalized, so
existing configs keep working:

```ruby
# Legacy (still supported)
{ type: :string, dbcolumn: :stage }

# Equivalent modern form (what it's normalized to internally)
{ type: :single, filter_type: :string, dbcolumn: :stage }
```

Nested legacy rules (`type: :nested`) keep `filter_type:` as-is and
only get `type: :nested` normalized alongside it.

## Error handling

`BharatFilterEngine::Errors` defines a small hierarchy you can rescue
from if you extend the engine:

```ruby
BharatFilterEngine::Error                 # base class
BharatFilterEngine::InvalidConfigurationError
BharatFilterEngine::InvalidFilterError
BharatFilterEngine::InvalidAssociationError
```

Invalid associations/columns referenced via `__` notation don't raise
by default — `AssociationResolver` and `DynamicFilterValues` simply
return `nil`, and `Engine` skips filters whose association can't be
resolved, leaving the scope unchanged.

## Running the test suite

```bash
bundle install
bundle exec rspec
```

The specs run against an in-memory SQLite database defined in
`spec/spec_helper.rb`, so no external database setup is required.

## Contributing

Bug reports and pull requests are welcome. Please add/update specs for
any behavior change, and run `bundle exec rspec` before opening a PR.

## License

The gem is available as open source under the terms of the
[MIT License](LICENSE).
