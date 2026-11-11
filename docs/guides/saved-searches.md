# Saved searches

People can save the query in the box under a name and run it again later.
querylane decides what may be saved; your app stores it.

## Turning it on

```ruby
d.saved store: "SavedSearchStore"
```

The box gets a **Saved** button that opens a popover with a name field, a Save
button and the user's saved searches. Each saved entry also has a delete
control, with a confirmation before it is removed.
The entry shares one hover/focus highlight. Apply and Delete remain separate
sibling buttons with non-overlapping click targets; the trash icon sits
inside the row, not inside the Apply button.

## The store contract

`store` is an object, or a class or module name resolved on every call. It
responds to four methods. Each gets the request's `Querylane::Context` as
`context:` so you can scope by user.

| Method | Returns |
| --- | --- |
| `all(context:)` | The user's saved searches, in the order to show them. Each responds to `id`, `name`, `query` and `used_at` (a time or `nil`) |
| `create(context:, name:, query:)` | Anything (ignored) |
| `use(context:, id:)` | The saved search with that id, or `nil`. Record that it was used here |
| `delete(context:, id:)` | `true` after deleting the current user's selected entry; `false` for a missing or unowned entry, or no current user. Scope the lookup before deleting, never trust the submitted id alone |

The dummy app keeps them in memory:

```ruby
module MemorySavedSearches
  Saved = Struct.new(:id, :name, :query, :used_at)

  module_function

  def items = (@items ||= [])

  def all(context:) = items.sort_by { |saved| saved.used_at || Time.at(0) }.reverse

  def create(context:, name:, query:)
    @next_id = (@next_id || 0) + 1
    items << Saved.new(@next_id.to_s, name, query, nil)
  end

  def use(context:, id:)
    items.find { |saved| saved.id == id.to_s }&.tap { |saved| saved.used_at = Time.current }
  end

  def delete(context:, id:)
    saved = items.find { |item| item.id == id.to_s }
    saved ? !!items.delete(saved) : false
  end
end
```

The reference store is a shared in-memory list, not an authorization example.
A database-backed store must scope deletion to the current user:

```ruby
class SavedSearchStore
  def self.all(context:) = context.user.saved_searches.order(used_at: :desc)

  def self.create(context:, name:, query:) = context.user.saved_searches.create!(name: name, query: query)

  def self.use(context:, id:)
    context.user.saved_searches.find_by(id: id)&.tap { |saved| saved.touch(:used_at) }
  end

  def self.delete(context:, id:)
    return false unless context.user && id.to_s.match?(/\A[1-9]\d*\z/)

    saved = context.user.saved_searches.find_by(id: id)
    return false unless saved

    saved.destroy!
    true
  end
end
```

Pass the user in the context from your controller:

```ruby
querylane_search(PEOPLE, scope: scope, context: Querylane::Context.new(user: current_user, request: request))
```

## How it behaves

- **Save** sends `save_search=1` and `saved_name`. The name is squished and cut
  to 80 characters; without one, the query text (first 80 characters) is the
  name. A blank or invalid query saves nothing.
- **Choosing a saved search** sends `saved=<id>` (at most 64 characters). The
  store's `use` returns it and the server replaces the box with its query, even
  when the box held an unfinished or invalid query.
- The Saved star is filled while the box holds exactly the text of one of the
  user's saved searches.
- After saving, a notice says "Search saved."
- **Delete** asks "Delete this saved search?". Cancel changes nothing;
  confirmation sends `delete_saved=<id>` and `delete_saved_page=<current page>`
  through the existing POST form and its CSRF token. The host must authorize
  access before calling `querylane_search`; a denied scope never calls deletion.
- Successful deletion says "Search deleted." and refreshes the saved list.
  The current query, sort and page remain unchanged. The star stays filled if
  another saved entry has the same query. Deleting the final entry shows
  "Nothing saved yet.".
- Missing and unowned entries both say "Saved search is not available.".
  GET deletion is rejected even when `allow_get_query` is enabled. Stores
  without `delete` return the unavailable-entry notice rather than mutating data.
- A host with an `icon` helper supplies `icon("trash-2")`; otherwise the
  control reads "Delete". Its accessible label and tooltip identify the entry.

## What is refused

A query that holds a sensitive value is never saved. That covers:

- a term of a sensitive operator, at any depth (inside `OR`, `NOT` or
  parentheses): `ssn:123456789`, `last4:5432`;
- a bare token the interpreter read as a sensitive operator: `smith 5432`;
- any value the interpreter *would* read as sensitive, however it was typed:
  a quoted `"123456789"`, or `name:123456789`.

The popover explains the refusal before the user tries, and disables Save:

> **Cannot save:** "5432" is read as last four. Saved searches never keep member
> IDs, SSNs or last fours, even when the box worked them out. Remove it, or save
> "smith" alone.

The value in that message is masked with its operator's mask. If a save is
attempted anyway, nothing is stored and the notice says "This search was not
saved: it holds a member ID, SSN or last four." (Change these sentences through
[translations](theming.md#translations).)

## When the store fails

Any exception from the store is caught. The search still runs, the notice says
"Saved searches are unavailable right now.", and
`saved_search_failed.querylane` is published with the definition name and the
exception class.

## Testing your store

`Querylane::Saving.refusal(query)` tells you whether a query may be saved:

```ruby
query = Querylane::Query.analyze(PEOPLE, "smith 5432")
refusal = Querylane::Saving.refusal(query)
refusal.value    # => "5432" (masked per the operator)
refusal.operator # => "Last four"
refusal.rest     # => "smith"
```
