# Controller

Include `Querylane::Controller` in the controller that serves a search page:

```ruby
class SearchesController < ApplicationController
  include Querylane::Controller
end
```

The view helpers (`querylane_form`, `querylane_results` and the rest) are added
to every `ActionController::Base` view by the engine.

## The calls

Every call takes the definition and keyword arguments. Every call that reads
query text first runs the [guard](#the-guard).

### `querylane_search`

```ruby
querylane_search(definition, scope:, context: Querylane::Context.new(request: request), params: self.params)
# => Querylane::Result
```

Runs one search for this request: applies any rewrite the request asks for
(facet toggle, chip ×, Clear, "instead", widen, Fix it, options panel, saved
search), checks the query, searches, and returns a `Querylane::Result` for the
partials. It never raises for a bad query or an unreachable backend; those are
the `:invalid` and `:unavailable` states. It does raise `Querylane::HookError`
when a hook fails ([Scope and hooks](scope-and-hooks.md#failing-closed)).

`scope:` is required and must be a `Querylane::Scope`; anything else raises
`Querylane::MissingScopeError` ([Scope and hooks](scope-and-hooks.md)).

### `querylane_frame?`

```ruby
querylane_frame?(id, part = :results) # => true or false
```

Whether this request was sent by one frame of a widget: it compares the
`Turbo-Frame` header with `"#{id}-#{part}"`. Use it to render just the frame:

```ruby
render partial: "searches/results", locals: {result: @result} if querylane_frame?(:people)
```

Parts you will meet: `:results`, `:writes` (options panel preview), `:list`
(suggest box), `:preview`.

### `querylane_preview`

```ruby
querylane_preview(definition, params: self.params) # => Querylane::Preview
```

What the options panel would write, without searching. Render it with the
`querylane/writes` partial:

```ruby
if querylane_frame?(:people, :writes)
  return render partial: "querylane/writes", locals: {preview: querylane_preview(DummySearch.definition), id: "people"}
end
```

`Preview#text` is the composed query and `#kept` the parts kept as typed, both
with sensitive values masked. `#error` is set when the fields would write a query
that cannot run.

### `querylane_related`

```ruby
querylane_related(definition, scope:, context: ..., params: self.params) # => Querylane::Result or nil
```

All records of one group, for "more records" and the preview. It returns `nil`
when the request has no `group` parameter, so you can try it first:

```ruby
if (related = querylane_related(DummySearch.definition, scope: scope))
  return render html: helpers.querylane_related(related, id: :people, presenter: PersonPresenter, frame: request.headers["Turbo-Frame"])
end
```

The search finds every record whose group attribute equals the token's value,
any status, inside the scope and query-filter hooks, sorted by the group's
`order` (or the default sort), up to the group's `limit`. The query text is
ignored. An invalid, expired or foreign token gives the `:unavailable` state
("These records could not be loaded").

The helper of the same name renders the right partial for the frame that asked:

```ruby
helpers.querylane_related(result, id:, presenter:, frame:)
```

`frame` is the requesting frame id (the `Turbo-Frame` header). For
`"#{id}-preview"` it renders `querylane/preview`; otherwise `querylane/related`.
A frame id that is not `"#{id}-related-<16 hex>"` is replaced, so a request can't
choose an arbitrary id.

### `querylane_suggest`

```ruby
querylane_suggest(definition, scope:, context: ..., params: self.params) # => Querylane::Result
```

Suggestions for a header box or palette: operator completions for the last
word and people for the rest of the text. A backend failure leaves only the
completions (state `:unavailable`). Render it with `querylane_suggestions`:

```ruby
def suggest
  result = querylane_suggest(DummySearch.definition, scope: scope)
  id = %w[find palette].find { |candidate| querylane_frame?(candidate, :list) } || "find"
  render html: helpers.querylane_suggestions(result, id: id, presenter: PersonPresenter)
end
```

One endpoint can serve several suggest boxes: answer with the id of the frame
that asked.

## A full search action

This is the dummy app's action. The order matters: the `writes` frame, then a
group request, then the search.

```ruby
def search
  if querylane_frame?(:people, :writes)
    return render partial: "querylane/writes", locals: {preview: querylane_preview(DummySearch.definition), id: "people"}
  end

  if (related = querylane_related(DummySearch.definition, scope: scope))
    return render html: helpers.querylane_related(related, id: :people, presenter: PersonPresenter, frame: request.headers["Turbo-Frame"])
  end

  @result = querylane_search(DummySearch.definition, scope: scope)
  if querylane_frame?(:people)
    render partial: "searches/results", locals: {result: @result}
  else
    render :show
  end
end
```

The `else` branch serves full-page POSTs: "Search all" and "Open search options"
from a suggest box, or a browser without JavaScript.

## The guard

`querylane_search`, `querylane_preview`, `querylane_related` and
`querylane_suggest` all run the same guard:

- A GET whose **URL query string** carries the query parameter
  (`search_query`), `compose` or `group` raises `ActionController::BadRequest`
  (400), unless `config.allow_get_query` is on. Only the URL is checked. Your
  code may still pass a query it restored on the server (for example a
  remembered search) to a GET through `params:`.
- The response gets `Cache-Control: no-store`.

## Params

The request is read by `Querylane::Request.from_params`. Everything is
allowlisted against the definition; unknown values fall back to defaults.

| Param | Meaning |
| --- | --- |
| `search_query` | The box text (`config.param_name`) |
| `revision` | The box's revision counter, echoed back on the frame |
| `toggle` | `facet:value` to tick or untick |
| `remove` | Chip index to remove |
| `clear` | Empty the box |
| `instead` | `chip.alternative`, another reading of an interpreted term |
| `widen` | A facet key whose terms to drop |
| `relax` | Match fewer name words |
| `fix` | Apply the error's correction |
| `options` | Open the options panel |
| `compose[...]` with `compose_submit` | Options panel fields to write into the box |
| `compose_preview` | The panel's "Writes" request (answer with `querylane_preview`) |
| `group` | A group token (`querylane_related`) |
| `saved` | A saved search id to run |
| `save_search`, `saved_name` | Save the current query under a name |
| `sort` | A sort key |
| `per` | A page size from the definition |
| `page` | Page number; any rewrite resets it to 1 |

## Context

`Querylane::Context` carries facts your hooks and saved-search store may need:

```ruby
Querylane::Context.new(user: current_user, request: request, extras: {tenant: current_tenant})
```

The default is `Context.new(request: request)`. Build it on the server, never
from params.

## Instrumentation

Searches publish `search.querylane` through `ActiveSupport::Notifications` with
`definition`, `state` (including `:related` and `:suggest`), `backend_calls`,
`hits` and `duration_ms`. The payload never holds query text. A failing
saved-search store publishes `saved_search_failed.querylane` with `definition`
and `error` (the exception class name).

```ruby
ActiveSupport::Notifications.subscribe("search.querylane") do |event|
  Rails.logger.info("search #{event.payload[:definition]} #{event.payload[:state]} #{event.payload[:duration_ms]}ms")
end
```

## Calling the search without a controller

```ruby
request = Querylane::Request.new(definition: PEOPLE, query: "smith team:ops")
result = Querylane::Search.new(definition: PEOPLE, request: request, scope: scope, context: context).call
```

`Search` also takes `searcher:` to use a searcher other than the configured one.
