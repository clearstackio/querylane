# Presenter

A presenter says how your records look in the result rows. Your Ruby decides
the content; the gem's partials (`querylane/_rows`, `_group`, `_record`,
`_outcome`) draw it. Subclass `Querylane::Presenter` and override what you need:

```ruby
class PersonPresenter < Querylane::Presenter
  def columns = [Column.new(:team, "Team", 120), Column.new(:started, "Started", 100)]

  def subtitle(group) = "•••-#{group.hits.first.document["id_last4"]}"

  def note(group)
    "matched on name" if result.query.present?
  end

  def cells(hit) = [Cell.new(hit.document["team"], :strong), Cell.new(hit.document["started"], :muted)]

  def status(hit)
    (hit.document["status_label"] == "active") ? Badge.new("Active", :success) : Badge.new("Terminated", :neutral)
  end

  def flags(hit) = hit.document["combo"] ? [Badge.new("Combo", :neutral)] : []

  def outcome(hit)
    if hit.document["status_label"] == "terminated"
      return Reason.new(text: "Terminated. Rehire them first.", link_label: "Rehire", link_url: "/rehire",
        more: ["Combo-billed division."])
    end

    Action.new("Open ▸", view.open_record_path, {id: hit.id, index: hit.index}, :primary)
  end
end
```

Pass the class (not an instance) to `querylane_results`, `querylane_related` and
`querylane_suggestions`. The helpers build it with `new(result, view, id:)`.

Inside a presenter you have:

- `result`: the [`Querylane::Result`](#the-result) being drawn.
- `view`: the view context, for route helpers, `t`, `link_to` and
  `querylane_highlight`.
- `id`: the widget id, as a String.

## Hits

Each record is a `Querylane::Result::Hit`:

| Field | Meaning |
| --- | --- |
| `index` | The logical index key (`:staff`) |
| `id` | The document id, as a String |
| `document` | The retrieved attributes (string keys) |
| `formatted` | Highlighted values; use `view.querylane_highlight(hit, :full_name)` |
| `ranking_details` | The backend's ranking score details |
| `contributors` | Other hits a results hook merged into this one |

`view.querylane_highlight(hit, attribute)` escapes the value and wraps matched
words in `<mark>`. It falls back to the plain document value.

## Value objects

| Class | Fields | Notes |
| --- | --- | --- |
| `Column` | `key, label, width` | `width` in pixels; `nil` takes the remaining space |
| `Cell` | `text, style` | `style`: `:strong`, `:muted` or `nil` |
| `Badge` | `text, tone` | `tone`: `:success`, `:warning`, `:danger`, `:info`, `:neutral` |
| `Action` | `label, url, params, style` | A button that POSTs `params` to `url` as a full page (Turbo off), drawn as a Go link (`.ql-go`). `style` is kept for hosts and no longer changes the look |
| `Reason` | `text:, link_label: nil, link_url: nil, more: []` | Why a record cannot be opened, with an optional link. `more` lists further reasons behind "+N more" |
| `Group` | `key, hits` | One group of hits |
| `Suggestion` | `detail, badge, action` | How a group appears in suggestions |

Pressing Enter on a focused record clicks its Action button.

## Methods you override

| Method | Default | Returns |
| --- | --- | --- |
| `columns` | `[]` | Your lanes, as `Column`s |
| `cells(hit)` | `[]` | One `Cell` per column |
| `status_label` | `"Status"` | Header of the status lane; `nil` removes the lane |
| `status(hit)` | `nil` | A `Badge` for the status lane |
| `flags(hit)` | `[]` | Small `Badge`s after the status lane |
| `outcome_label` | `"Open"` | Header of the last lane |
| `outcome(hit)` | `nil` | An `Action`, a `Reason` or `nil` |
| `title(group)` | the first `highlight` attribute of the group's first hit, highlighted | Group heading (HTML-safe) |
| `subtitle(group)` | `nil` | Text next to the title |
| `note(group)` | `nil` | Why the group matched |
| `group_key(hit)` | the definition's `group` attribute | The value that groups hits; `nil` keeps a hit alone |
| `suggestion(group)` | see below | A `Suggestion` |
| `record_key(hit)` | 16 hex characters of SHA-256 of `index:id` | An opaque, stable key for focus and tests |

If you override `group_key`, return the value of the definition's `group`
attribute: "more records" searches for exactly that value.

## Groups

`groups` walks the hits in rank order. The best-ranked hit of each group decides
where the group sits. Inside a group, records follow the definition's
`group ... order:` when it has one (`order_records`), otherwise rank order.

For each group the gem also uses:

- `group_token(group)`: the encrypted handle for "more records" and the preview,
  or `nil` when the group has no value or the definition has no `group`.
- `more_count(group)`: how many of the group's records the page does not show,
  or `nil`. "N more records" shows only when this is positive. It compares the
  records on the page (counting merged contributors) with `result.group_totals`,
  which the search fills by asking the searcher for each group value's record
  count within the scope. If that count fails, `group_totals` is `nil` and the
  link stays hidden.
- `related_frame_id(group)`: the id of the group's "more records" frame.

## Suggestions

In the header box and the palette, each group is one option. The default
`suggestion(group)`:

- `detail`: "1 record" or "N records" (`querylane.suggest.records`).
- `badge`: the first record's `status`.
- `action`: the Action of the group's only openable record, when exactly one
  record has an Action. Choosing the option clicks it. Otherwise choosing it runs
  the full search.

Override it to change any of those:

```ruby
def suggestion(group)
  Suggestion.new("#{group.hits.size} policies", status(group.hits.first), nil)
end
```

## The result

A presenter can read anything on `result`, for example `result.query` (the box
text) or `result.definition`. Useful fields:

| Field | Meaning |
| --- | --- |
| `state` | `:first_load`, `:short`, `:ok`, `:empty`, `:invalid`, `:unavailable`, `:denied` |
| `query` | The query text after any rewrite |
| `hits`, `total`, `total_kind` | The page of hits; the total; `:exact`, `:capped` or `:estimated` |
| `page`, `per`, `pages`, `sort` | Paging and sorting |
| `chips`, `facets`, `error` | What the page shows |
| `merged` | A results hook merged hits on this page |
| `group_totals` | Records per group value (down-cased keys), or nil |

## Drawing rows yourself

Pass a block to `querylane_results` instead of a presenter, and draw
`result.hits` your way. Grouping, "more records" and the preview then depend on
your markup: the results controller looks for `[data-querylane-record]`
(focusable records), `[data-querylane-group]` (holding a group token) and
`[data-querylane-open]` (the button Enter clicks).
