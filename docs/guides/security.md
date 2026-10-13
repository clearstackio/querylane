# Security and privacy

querylane was built for searching people by name and ID. Its defaults assume
that query text can hold private data (a social security number, a member ID)
and that every result must stay inside what the user may see. This page lists
what the gem guarantees and what your app must do. To report a vulnerability,
see [SECURITY.md](../../SECURITY.md).

## What querylane guarantees

### Authorization

- Every search needs a server-built `Querylane::Scope`. Without one, the search
  raises before any backend call.
- The scope's permission filter is ANDed into every hit query, count query,
  facet count, group count, "more records" query and suggestion query.
- An index whose filter matches nothing is not queried at all, so a "nothing"
  filter never turns into an unrestricted query.
- `Scope.denied` searches nothing and says so.
- Query-filter hooks can only narrow the scope. Results hooks can only keep or
  merge hits they were given. A hook that fails or breaks its contract aborts the
  request ([fail closed](scope-and-hooks.md#failing-closed)).
- A backend failure shows "Search is not answering", never stale or partial
  hits. If only the count batch fails, hits stay and counts are marked
  unavailable.

### Query text in transit

- Query text travels by POST only. A GET whose URL query string carries the
  query, panel fields (`compose`) or a group token is refused with 400, unless the
  host sets `config.allow_get_query = true`.
- "Search all" and "Open search options" from a suggest box are full-page POSTs,
  not links.
- Every querylane response is sent with `Cache-Control: no-store`.

### Logs

The engine adds the query parameter (`search_query`) and `compose` to
`config.filter_parameters`, so Rails logs show `[FILTERED]`.

The filter is set once, at boot, from the `param_name` in effect then. If you
change `config.param_name` in an initializer, add the new name yourself:

```ruby
Rails.application.config.filter_parameters += [:people_query]
```

Instrumentation events (`search.querylane`, `saved_search_failed.querylane`)
never carry query text. Hook errors name the hook and the exception class only.

### What reaches the page

- Chips mask sensitive values with the operator's `mask`.
- Validation errors never repeat a sensitive value ("That value is not a valid
  ssn: value.").
- The options panel never fills a masked field with a value. Masked terms stay
  in the box, and the field's placeholder shows them masked. The "Writes"
  preview masks them too.
- Suggestions never repeat the query in attributes. "Search all for …" shows the
  text with sensitive values masked. A completion carries only its word.
- Highlighted text is escaped first. Only querylane's private marker characters
  become `<mark>` tags.
- Record keys on the page are hashes of `index:id`, not the ids.

The box itself holds what the user typed, by design. When the server rewrites
the query (a facet toggle, chip ×, the options panel) it sends the new text back
inside the frame as a `querylane_set_query` stream, and on a full-page render the
input's `value` attribute holds it. Masking in the box (`mask:` on
`querylane_form`) is visual only.

### Group tokens

"More records" and the preview need to say which group to load. The page never
holds the group value (for example a member ID). It holds a token:

- encrypted and signed with `ActiveSupport::MessageEncryptor`, using a key
  derived from your app's `secret_key_base`;
- bound to the definition's name (a token for one definition is rejected by
  another);
- expiring after `config.group_token_ttl` seconds (default one hour);
- holding the group value and the `index:id` of the records already shown.

A tampered, expired or foreign token gives "These records could not be
loaded." A valid token still searches inside the current user's scope: a token
cannot reach records the user may not see.

### Saved searches

A query with a sensitive term, typed or interpreted, at any depth, is never
saved. Values the interpreter would read as sensitive are refused even when
quoted or put under another operator. See
[Saved searches](saved-searches.md#what-is-refused).

### Browser history and cache

Before Turbo snapshots a page, the box and suggest box clear their input, the
results frame and the suggestion list. Back and forward never bring query text
or results back.

### Typo tolerance

The doctor asks for typo tolerance to be off on the attributes of sensitive text
operators, so an ID prefix never matches a different ID that is "close".

## What your app must do

- **Build the scope on the server** from the signed-in user, for every request.
  Use `Scope.denied` when you cannot check access. Never accept index names or
  filters from params.
- **Filter a renamed query parameter** from logs (see [Logs](#logs)).
- **Keep request bodies out of APM and error reports.** Query text is in the
  POST body. Configure your APM, error tracker and reverse-proxy logs not to
  record request bodies, or to filter `search_query` and `compose`.
- **Keep `allow_get_query` off** unless you have a reason and have checked where
  URLs are logged.
- **Mark private operators** `sensitive: true` and give them a `mask`. Do not
  declare facets on them (the gem refuses).
- **Turn off typo tolerance** where the doctor asks.
- **Protect the Open action.** A presenter's `Action` posts params you choose to
  a URL you choose; authorize that endpoint like any other.
- **Store saved searches per user** (use `context:`), and treat their text as
  user data.
- **Keep `secret_key_base` secret.** It protects group tokens.
