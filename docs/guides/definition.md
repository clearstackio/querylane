# Definition reference

A definition says what a search understands: which indexes it reads, which
operators people can type, and how facets, sorts, groups and the options panel
behave. You build it once with `Querylane::Definition.build`:

```ruby
PEOPLE = Querylane::Definition.build(:people) do |d|
  d.index :staff, name: "staff"
  d.text  :name, attributes: %i[full_name], default: true
end
```

- The name (`:people`) identifies the definition in instrumentation and binds
  group tokens to it.
- `build` validates the declarations and returns a frozen object. Mistakes raise
  `Querylane::ConfigurationError` with the definition name in the message.
- Host classes can be referenced by name as a String (`"PeopleRules"`). They are
  resolved on every call, so code reloading never leaves stale methods. This
  applies to flag `rules:`, `interpreter`, `group valid:`, `saved store:` and
  hooks.
- Every definition needs at least one `index` and one `text` operator.

Operator keys and aliases share one namespace. Declaring a key twice raises.

## Indexes

### `index(key, name:)`

A logical index and its backend name. `name` is a String or a callable that
returns one (useful for per-environment names).

```ruby
d.index :staff, name: -> { "staff_#{Rails.env}" }
d.index :contractors, name: "contractors"
```

The search reads the indexes listed in the [Scope](scope-and-hooks.md), not
every declared index. Hits from all indexes are merged into one ranked list.

## Operators

There are three kinds: text operators (free text), filters (exact match) and
flag families (named values).

### `text(key, attributes:, sensitive: false, default: false, label: nil, mask: nil)`

Free text searched in `attributes`.

```ruby
d.text :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
d.text :id, attributes: %i[memberid], sensitive: true, label: "Member ID starting %{value}"
```

| Option | Meaning |
| --- | --- |
| `attributes` | Attributes to search (`attributesToSearchOn`) |
| `default` | Bare words go to this operator. Without one, the first text operator is the default |
| `label` | Chip text; `%{value}` is replaced by the words. Default: `"<Key> %{value}"` |
| `sensitive` | The value is private (an ID). Masks chips, keeps it out of saved searches, and the doctor asks for typo tolerance to be off on its attributes |
| `mask` | How chips show the value: `:none`, `:all`, `:last4`, `:count`. Default: `:all` when sensitive, else `:none` |

A query may use only one text operator. `smith id:12345` is an error. Text words
can't appear inside `OR`, `NOT` or parentheses.

### `filter(key, attribute:, sensitive: false, normalize: nil, format: nil, label: nil, mask: nil)`

An exact match on one attribute (`attribute = value`).

```ruby
d.filter :team, attribute: :team, label: "Team %{value}"
d.filter :ssn, attribute: :memberid, sensitive: true, normalize: :digits, format: /\A\d{9}\z/,
  label: "SSN %{value}", mask: :last4
```

| Option | Meaning |
| --- | --- |
| `normalize` | Runs on the typed value first. `:digits`, `:upcase`, `:downcase`, `:strip`, or any callable taking and returning a String |
| `format` | A Regexp the normalized value must match. If it does not, the query is invalid |
| `sensitive` | As for `text`. The format error says "That value" instead of repeating it. Sensitive filters cannot have facets |
| `label`, `mask` | As for `text` |

Masks, for a value `123456789`:

| Mask | Chip shows |
| --- | --- |
| `:none` | `123456789` |
| `:all` | `•••••••••` |
| `:last4` | `•••-••-6789` (values shorter than 4 become dots) |
| `:count` | `9 characters` (from the `querylane.chips.count` translation) |

In query text (the options panel preview, the suggestion "Search all for …"
line), `:count` shows as dots instead.

### `flags(key, values:, alias: nil, attribute: nil, rules: nil, label: nil)`

A family of named values, typed as `key:value` (`is:active`).

```ruby
d.flags :is, alias: :status, attribute: :status_label, label: "Status",
  values: {active: "Active", terminated: "Terminated"}

d.flags :has, rules: "MemberRules", label: "Has", values: {combo: "Combo"}
```

| Option | Meaning |
| --- | --- |
| `values` | A Hash of value → label, or an Array of values (labels are humanized). Values are matched case-insensitively |
| `alias` | Another key, or an Array of keys, for the same family (`status:active` = `is:active`) |
| `attribute` | `is:active` means `status_label = "active"` |
| `rules` | An object or class name with one method per value. Each takes `index:` (the logical index) and returns a [`Querylane::Filter`](scope-and-hooks.md#the-filter-api) |
| `label` | Chip prefix: `Status Active`. Default: the humanized key |

Give exactly one of `attribute:` or `rules:`. Rules let a value mean different
things per index, or a combination of attributes:

```ruby
module MemberRules
  module_function

  def combo(index:) = (index == :ebmr) ? Querylane::Filter.eq(:combo, true) : Querylane::Filter.eq(:combo, "C")
end
```

## Facets

### `facet(key, label: nil, flag: nil, filter: nil, top: 10, values: nil, show: nil, search: false)`

A list of values with counts beside the results. Clicking a value ticks or
unticks it in the query text.

```ruby
d.facet :status, flag: :is
d.facet :can_open, flag: :is, values: %i[openable not_openable], label: "Can open"
d.facet :team, filter: :team, top: 5, show: 1, search: true
```

| Option | Meaning |
| --- | --- |
| `flag` | A flag family key. Counts every value (or `values`) |
| `filter` | A filter key. Shows the `top` most common values |
| `values` | Flag facets only: a subset of the family's values. Lets one family feed several facets |
| `top` | Filter facets: how many values to load. Default 10 |
| `show` | How many values to show before the rest are hidden. Default: `top` |
| `search` | Adds a "Find…" box that filters the loaded values in the browser. Shown only when there are more values than `show` |
| `label` | Facet heading. Default: the humanized key |

Give `flag:` or `filter:`. A facet cannot use a sensitive operator.

Counts follow the usual faceted-search rule: values in one facet combine with OR,
different facets combine with AND. A facet's counts are computed without its own
ticked values, so unticked counts show what ticking them would add. Ticked values
always show, even outside the top values. Filter facets with 100 or more values
(Meilisearch's default `maxValuesPerFacet`) show counts as approximate (`~`).

## Sorting and paging

### `sort(key, label: nil, by: nil, default: false)`

```ruby
d.sort :best, label: "Best match", default: true
d.sort :name, label: "Name A–Z", by: {full_name: :asc}
d.sort :recent, label: "Newest", by: {started: :desc, full_name: :asc}
```

`by` maps attributes to `:asc` or `:desc`. `nil` means relevance. Only one sort
can be the default; without one, the first is. With no sorts declared, there is
one: `:best`, "Best match".

### `per(*sizes)`

Page sizes offered in the toolbar. The first is the default. Default: `25, 50, 100`.

```ruby
d.per 25, 50, 100
```

## What comes back from the backend

### `retrieve(*attributes)`

The attributes each hit returns (`attributesToRetrieve`). Without it, the backend
returns every displayed attribute. List everything your presenter reads,
including the group attribute.

```ruby
d.retrieve %i[id person full_name team status_label started]
```

### `highlight(*attributes)`

Attributes whose matched words are highlighted. Default: every text operator's
attributes. The first one is the presenter's default group title.

```ruby
d.highlight :full_name
```

## Reading bare tokens

### `interpreter(reference)`

Reads a bare, unquoted word as an operator. The interpreter is any object (or
class name) that responds to `call(token)` and returns `[operator_key, value]` or
`nil`. It sees every bare word, so return `nil` for names. Your rules decide the
order.

```ruby
module PeopleInterpreter
  module_function

  def call(token)
    case token
    when /\A\d{9}\z/ then [:ssn, token]
    when /\A\d{6}\z/ then [:policy, token]
    when /\A\d{4}\z/ then [:last4, token]
    end
  end

  # Optional: other readings, offered as "Policy 5432 instead" next to the chip.
  def alternatives(token)
    token.match?(/\A\d{4}\z/) ? [[:policy, token]] : []
  end
end

d.interpreter "PeopleInterpreter"
```

A lambda works when you need no alternatives:

```ruby
d.interpreter ->(token) { [:last4, token] if token.match?(/\A\d{4}\z/) }
```

The value is then validated like a typed `last4:5432` (normalize, format). Quoted
words (`"5432"`) are never interpreted.

### `parked(*keys)`

Operator names reserved for later. Using one gives "first: is not available
yet." instead of "first: is not an operator."

```ruby
d.parked :first, :last
```

### `min_text_length(length)`

When every word is shorter than `length` and the query has nothing else (no
operator, no interpreted token), the search does not run. The page says "Type at
least 3 letters…" and the box keeps the last results. `*` does not count toward
the length.

```ruby
d.min_text_length 3
```

## Groups

### `group(attribute, valid: nil, limit: 20, order: nil)`

Hits that share `attribute` (for example a person ID present in every index) are
shown as one group. A group can load every record it has ("N more records") and
can be previewed with Space.

```ruby
d.group :person
d.group :memberid, valid: ->(value) { value.match?(/\A\d{9}\z/) }, limit: 50, order: {status_rank: :asc, started: :desc}
```

| Option | Meaning |
| --- | --- |
| `valid` | A callable (or class name) that returns false for values that must not group, such as placeholders. Those hits stand alone |
| `limit` | Most records loaded for "more records" and the preview. Default 20 |
| `order` | How a group's records are ordered: attributes mapped to `:asc` or `:desc`. Default: relevance |

With `order`, the records inside each group on the page are sorted by it (a
stable sort that compares the values as strings), and "more records" and the
preview ask the backend to sort by it, so all three agree. The best-ranked
record still decides where the group sits on the page. The `order` attributes
must be sortable in the index.

"N more records" appears only when the group has records the page does not
show. To know that, each search asks the searcher for the number of records per
group value on the page (see [Presenter](presenter.md#groups)).

The group value never reaches the page. The page carries an encrypted, expiring
[group token](security.md#group-tokens) instead. The attribute must be filterable.

## Saved searches

### `saved(store:)`

Turns on the Saved button. `store` is an object or class name; see
[Saved searches](saved-searches.md).

```ruby
d.saved store: "SavedSearchStore"
```

## The options panel

The options panel shows the query as form fields. Without any `panel`
declarations, it has one row per operator plus one row of all options.

### `option(key, label, text)`

A checkbox that stands for exact query text.

```ruby
d.option :exclude_terminated, "Exclude terminated", "-is:terminated"
```

The box text `smith -is:terminated` shows the checkbox ticked. Ticking it adds
the text; unticking removes it.

### `panel(label) { |p| p.row(label, *keys, bare: false, values: nil) }`

Lays out the panel in labelled groups of rows. Each row names operators or
options.

```ruby
d.panel "Who" do |p|
  p.row "Name contains", :name
  p.row "Member ID or SSN", :id, :ssn, bare: true
  p.row "Last four", :last4
end
d.panel "Where and status" do |p|
  p.row "Team", :team
  p.row "Status", :is, values: %i[active pending terminated]
  p.row nil, :exclude_terminated
end
```

A row is one of:

- **Inputs**: text and filter operators. One input per operator. With
  `bare: true`, one shared input whose text is written without a key, so the
  interpreter reads it (`5432`, not `last4:5432`).
- **Flags**: one flag family, shown as checkboxes. `values:` limits the row to
  some values; the rest stay in the box as typed.
- **Options**: option keys, shown as checkboxes.

A row can't mix flags with inputs or show two flag families. Unknown keys and
values raise at build time. The row label may be `nil`.

Rows whose operator has a mask other than `:none` are **masked**: the field
starts empty, its current terms stay in the box (shown masked as the field's
placeholder), and what is typed is hidden until "Show" is pressed.

Parts of the query the panel cannot show (OR groups across operators, negated
terms, terms for operators not in any row) are kept as typed.

### `example(query, description)`

An example query, shown on the first-load screen and in the syntax help.

```ruby
d.example "smith 5432", "a name and the last four"
d.example "team:ops -is:terminated", "everyone on ops still here"
```

## Hooks

### `hook(stage, reference, cardinality: :preserving)`

Runs your code inside every search. `stage` is `:query_filter` or `:results`.
See [Scope and hooks](scope-and-hooks.md#hooks).

```ruby
d.hook :query_filter, "TenantFilter"
d.hook :results, "Dedupe", cardinality: :changing
```

## A complete example

```ruby
MEMBERS = Querylane::Definition.build(:members) do |d|
  d.index :employees, name: -> { "employees_#{Rails.env}" }
  d.index :ebmr, name: -> { "ebmr_#{Rails.env}" }

  d.text :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
  d.text :id, attributes: %i[memberid], sensitive: true, label: "Member ID starting %{value}"
  d.filter :ssn, attribute: :memberid, sensitive: true, normalize: :digits, format: /\A\d{9}\z/, label: "SSN %{value}", mask: :last4
  d.filter :last4, attribute: :memberid_last4, sensitive: true, normalize: :upcase, format: /\A[0-9A-Z]{4}\z/,
    label: "Last four %{value}", mask: :none
  d.filter :policy, attribute: :policy_number, label: "Policy %{value}"
  d.flags :is, alias: :status, attribute: :status_label, label: "Status",
    values: {active: "Active", pending: "Pending", terminated: "Terminated"}
  d.flags :has, rules: "MemberRules", label: "Has", values: {combo: "Combo"}

  d.facet :status, flag: :is
  d.facet :policy, filter: :policy, top: 10, show: 5, search: true

  d.sort :best, label: "Best match", default: true
  d.sort :name, label: "Name A–Z", by: {full_name: :asc}
  d.per 25, 50, 100

  d.retrieve %i[id memberid memberid_last4 full_name policy_number status_label]
  d.interpreter "MemberInterpreter"
  d.group :memberid, limit: 20
  d.min_text_length 3
  d.parked :first
  d.saved store: "SavedSearchStore"

  d.option :exclude_terminated, "Exclude terminated", "-is:terminated"
  d.panel "Who" do |p|
    p.row "Name contains", :name
    p.row "Member ID or SSN", :id, :ssn, bare: true
  end
  d.panel "Where" do |p|
    p.row "Policy", :policy
    p.row "Status", :is
    p.row nil, :exclude_terminated
  end

  d.example "smith 5432", "a name and the last four"
  d.hook :query_filter, "TenantFilter"
end
```

## Reading a definition

These methods are useful in tests and custom partials:

| Method | Returns |
| --- | --- |
| `operator(key)` | The operator for a key or alias (case-insensitive), or nil |
| `operator_keys` | Every key and alias, as Strings |
| `default_text` | The default text operator |
| `facet(key)`, `sort(key)`, `option(key)` | One declaration (`sort` falls back to the default) |
| `texts`, `filters`, `flags`, `facets`, `sorts`, `per_options`, `options`, `examples`, `panel` | The declarations, in order |
| `index_name(key)` | The backend name of a logical index |
| `interpret(token)`, `alternatives(token)` | What the interpreter makes of a token |
| `group_value(document)` | A document's group value, or nil |
