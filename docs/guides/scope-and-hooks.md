# Scope and hooks

querylane never decides who may see what. Your app does, by building a
`Querylane::Scope` on the server for every request. Hooks let your code narrow a
search further or adjust its hits.

## Scope

A scope lists the logical indexes the user may search and a permission filter
for each:

```ruby
Querylane::Scope.new(
  staff: Querylane::Filter.everything,
  contractors: Querylane::Filter.eq(:team, "ops")
)
```

- Every hit, total, facet count, "more records" and suggestion query ANDs the
  index's permission filter.
- Only the indexes in the scope are searched. An index whose filter (combined
  with the query) can match nothing (`Filter.nothing`) is not sent to the backend
  at all.
- Scope keys are the definition's logical index keys. An index the definition
  does not declare raises `Querylane::ConfigurationError` when searched.
- Every index needs a filter. `nil` raises `Querylane::MissingScopeError`, and so
  does an empty scope.
- `Querylane::Search` (and so every controller call) raises
  `MissingScopeError` unless it gets a `Scope`.

Build the scope from the current user, never from params:

```ruby
def scope
  companies = current_user.company_ids
  Querylane::Scope.new(employees: Querylane::Filter.in(:company_id, companies))
end
```

`Filter.in(:company_id, [])` would match nothing, which is the safe answer for a
user with no grants.

### `Scope.unrestricted`

No permission filter, chosen on purpose:

```ruby
Querylane::Scope.unrestricted(:staff, :contractors)
```

### `Scope.denied`

Use it when you could not check the user's access (the permission service is
down, for example):

```ruby
def scope
  Querylane::Scope.new(employees: permission_filter_for(current_user))
rescue PermissionService::Unavailable
  Querylane::Scope.denied
end
```

Nothing is searched. The page shows the `:denied` state ("No results: your access
could not be checked"). Suggestions show no people and "more records" shows
nothing.

## The Filter API

`Querylane::Filter` builds backend-neutral filter trees. The Meilisearch searcher
renders them as filter expressions.

| Constructor | Matches | Meilisearch |
| --- | --- | --- |
| `Filter.eq(:status, "A")` | attribute equals value | `status = 'A'` |
| `Filter.in(:team, %w[ops billing])` | attribute is one of the values | `team IN ['ops', 'billing']` |
| `Filter.null(:ended_on)` | attribute present and null | `ended_on IS NULL` |
| `Filter.missing(:ended_on)` | attribute absent | `ended_on NOT EXISTS` |
| `Filter.and(a, b, ...)` | all of them | `(a) AND (b)` |
| `Filter.or(a, b, ...)` | any of them | `(a) OR (b)` |
| `Filter.not(a)` | not `a` | `NOT (a)` |
| `Filter.everything` | every document | no filter |
| `Filter.nothing` | no document | the index is skipped |
| `Filter.raw("company_id IN [1, 2]")` | a backend expression you wrote | as given |

Values are quoted for you: strings in single quotes with `'` and `\` escaped;
`true`, `false` and numbers bare.

`and` and `or` simplify:

- `Filter.and()` with no filters, or only `everything`, is `everything`. Any
  `nothing` makes it `nothing`.
- `Filter.or()` with no filters, or only `nothing`, is `nothing`. So an empty
  list of grants never widens a scope. Any `everything` makes it `everything`.
- `Filter.not(everything)` is `nothing`, and the reverse.
- `nil` arguments are ignored.

`Filter.raw` is for expressions your code owns, such as a permission filter you
already have. Never build one from user input.

## Hooks

Hooks run your code inside every search. Declare them in the definition:

```ruby
d.hook :query_filter, "TenantFilter"
d.hook :results, "CollapseCopies", cardinality: :changing
```

The reference is an object or a class name (resolved on every call). Hooks run
in the order declared. They get the `Querylane::Context` the controller passed.

### Query-filter hooks

Called once per index in the scope, with `index:` and `context:`. Return a
`Querylane::Filter`. It is ANDed into the scope for that index, so it can only
narrow the search.

```ruby
module TenantFilter
  module_function

  def call(index:, context:)
    Querylane::Filter.eq(:tenant_id, context.user.tenant_id)
  end
end
```

They apply to the search, counts, "more records", group counts and suggestions.

### Results hooks

Called with the page of hits, `hits:` (frozen) and `context:`. Return an Array of
`Querylane::Result::Hit`. A hook may:

- keep a subset of the hits, in order;
- merge hits: return one hit whose `contributors` holds the others.

It may never add a record it was not given.

```ruby
module CollapseCopies
  module_function

  # Shows one row per document id; the copies become contributors.
  def call(hits:, context:)
    hits.group_by(&:id).map { |_id, copies| copies.first.with(contributors: copies.drop(1)) }
  end
end
```

`cardinality:` says what the hook does to the number of hits:

| Cardinality | Meaning |
| --- | --- |
| `:preserving` (default) | Keeps hits one for one. Returning the same hit twice raises |
| `:changing` | May drop or merge hits |

When a `:changing` hook changes the record count, or any hit has contributors,
the toolbar says "Copies of the same record are shown once on this page." The
footer's "Showing x to y" counts contributors, so it still matches the records
read.

Results hooks run on the search, "more records", the preview and suggestions.

### Failing closed

A hook that raises, returns something that is not a filter, or returns a record
it was not given aborts the search with `Querylane::HookError`. The message names
the hook and the exception class, never data. The error is not rescued: results
are never shown without the hook's filtering. Handle it as you would any server
error (your app's 500 page or a `rescue_from`).

## Errors

| Error | Raised when |
| --- | --- |
| `Querylane::ConfigurationError` | The definition or configuration is wrong |
| `Querylane::MissingScopeError` | A search was attempted without a Scope, or a Scope lacks a filter |
| `Querylane::HookError` | A hook failed or broke its contract |
| `Querylane::SearchUnavailable` | The backend failed. Caught by the search and shown as `:unavailable` |

All inherit from `Querylane::Error`.
