# Architecture

This page is for people changing querylane. It explains how a request flows
through the gem, why the pieces are shaped the way they are, and where the
decisions are recorded. For using the gem, start with the
[README](../README.md).

## Principles

- **The query text is the only search state.** Facets, chips, the options panel,
  "instead", widen and saved searches all rewrite the text on the server and send
  it back. There is no separate "selected facets" parameter, so the box and the
  page can never disagree.
- **One parser, one truth.** The server parses; the browser only colors
  characters ([ADR 0002](decisions/0002-own-query-parser.md)).
- **The server renders.** Partials draw; Ruby decides. JavaScript handles
  timing, focus and keys, never meaning.
- **Fail closed.** No scope, a failing hook or an unreachable backend never
  shows unfiltered or stale results.
- **One implementation per seam.** The searcher, interpreter, presenter, hooks,
  saved-search store and partials are seams with one default each. No registry
  or abstract base classes.

## Ownership

| querylane | The host app |
| --- | --- |
| Parsing, validation, errors with ranges, "did you mean" | Index documents, settings and their lifecycle (indexing is out of scope) |
| Compiling to backend filters; Meilisearch calls | Authorization, expressed as a `Scope` |
| Facet counting, highlighting | Domain rules: flag `rules`, interpreter, reasons |
| Request and Result contracts | Rows, through a `Presenter` |
| Form, box, chips, facets, toolbar, pager, states; Stimulus | Page layout, copy, theme |
| Privacy defaults; instrumentation without query text | Filtering renamed params; APM and log config |

## Request flow

```text
params ──► Request ──► Query.analyze ──► rewrite ──► Query (again) ──► Compiler ──► Searcher ──► Result ──► partials + Presenter
            (allowlist)  (parse, interpret,   (Rewriter)                (text + filter    (hits, counts,
                          validate)                                       per index)        group counts)
```

1. **Request** (`lib/querylane/request.rb`) reads params and allowlists them
   against the definition: sort and page size from the definition, page ≥ 1,
   toggle split into facet and value, chip and alternative indexes as integers.
   Any rewrite resets the page to 1.
2. **Query** (`query.rb`) runs the **Parser** (`parser.rb`) to get an AST
   (`ast.rb`), then resolves each term: bare unquoted words go through the
   interpreter, keys map to operators (aliases included), filters normalize and
   check their format, flags check their values. Text words may not sit inside
   OR, NOT or a group, and a query may use one text operator. A query has at most
   one error (`QueryError`: message, range, optional fix).
3. **Rewrite** (`Search#rewrite`) applies what the request asks: Clear, Fix it, a
   saved search, the options panel (`Rewriter.compose`), a facet toggle
   (`Rewriter.toggle`), widen (`Rewriter.without`), "instead"
   (`Rewriter.replace` on the chip's range) or chip × (`Rewriter.remove`). The
   new text is analyzed again, so bounds and validation still apply.
4. **States before searching.** Blank → `:first_load`. Invalid → `:invalid`.
   Too short → `:short`. `Scope.denied` → `:denied`. None of these call the
   backend.
5. **Compiler** (`compiler.rb`) turns the valid query into one text query (the
   default text words joined, `*` dropped, phrases quoted) with the attributes to
   search, plus a function from logical index to `Querylane::Filter` (flags with
   `rules` can differ per index). `relax` switches the matching strategy from
   `all` to `frequency`.
6. **Hooks.** Query-filter hooks narrow the scope per index
   (`Search#hooked_scope`).
7. **Searcher** (`searchers/meilisearch.rb`) makes two HTTP calls:
   - a federated `multi_search` for the page of hits across every index in the
     scope (`federation: {offset, limit}`), with highlight markers, ranking
     details and the sort;
   - one batched, non-federated `multi_search` for the exact total and every
     facet count (`hits_per_page: 0` queries). If it fails, hits stay and the
     total becomes the estimate.
   When the definition has a `group`, a third call counts records per group value
   on the page (`group_counts`), so "more records" shows only when there are more.
8. **Results hooks** keep or merge hits (`Search#run_result_hooks`).
9. **Result** (`result.rb`) holds everything a page needs: state, query text,
   whether it was rewritten, hits, total and its kind, facets, chips, error,
   panel and preview, saved searches and notice, group totals.
10. **Partials** (`app/views/querylane/`) draw it. Rows come from the host's
    **Presenter** (`presenter.rb`).

`Search#related` (a group's records) and `Search#suggest` (suggestions) follow the
same path with a fixed query: a group-attribute filter, or the text minus the
word being completed.

## Facets

A facet value is **ticked** when the query has, at top level, a positive term
for it (`is:active`) or an OR group made only of positive terms of that operator
containing it (`(team:ops OR team:billing)`). Keys compare after alias
resolution, values after normalization. Toggling removes every canonical
occurrence and appends one canonical expression with the new value set. Values
in any other shape (negated, mixed groups) are left alone.

Counts are disjunctive: each facet is counted against the query **without its own
canonical terms** (`Rewriter.without`), with every other constraint kept. Flag
facets with an `attribute` use the backend's facet distribution; rules-based
flags are counted value by value (never by subtraction). Filter facets use the
distribution for the top values, plus an explicit count for each ticked value
outside it.

## Frames, forms and timing

One form per widget (`#{id}-form`) sits **outside** every frame, so typing never
loses the caret. Every other control joins it with `form=`. Host row forms
(`button_to`) never nest inside it.

| Frame | Holds | Requested by |
| --- | --- | --- |
| `#{id}-results` | Chips, error, notice, saved popover, options panel, facets, toolbar, rows, footer | Typing, Enter, every button of the form |
| `#{id}-writes` | The options panel's "Writes" line | `compose_preview` |
| `#{id}-preview` | Every record of one group | Space on a record |
| `#{id}-related-<key>` | A group's records not on the page | Opening "more records" |
| `#{id}-list` | Suggestions | Typing in a suggest box |

Hits and counts always come from the same request, because every submission
targets the one results frame.

### The set-query stream

When the server rewrote the query, the results frame contains, inside the
`<turbo-frame>`:

```html
<turbo-stream action="querylane_set_query" target="people-box" data-revision="7"><template>smith is:active</template></turbo-stream>
```

`index.js` handles the `querylane_set_query` action by replacing
`event.detail.render` in a `turbo:before-stream-render` listener, so it never
imports Turbo and works with any Turbo 8 copy on the page. It dispatches
`querylane:set-query` on the box, and the box controller sets `input.value` in
place (no element replacement, so focus and the controller survive), moves the
caret to the end and repaints the overlay, but only if its revision still equals
the one in the stream.

### Revisions and stale responses

The revision counter is a hidden field of the form, outside anything a response
replaces.

- Each keystroke increments it and marks the frame `data-querylane-stale` (chips
  dim; their × buttons are disabled).
- Submitting a toggle, chip ×, Clear, options Search or a saved search increments
  it too. The server echoes the revision on the frame (`data-revision`) and on
  the stream. Applying the rewrite does not increment it, so the response's
  chips, results and new text all belong to the same revision.
- On `turbo:before-frame-render` the box controller wraps Turbo's `render`: at
  the moment of replacement, a response older than the current revision is
  dropped. Wrapping (rather than `preventDefault`, which pauses Turbo until
  resumed) keeps later renders flowing.

The suggest box uses the same scheme on its list frame. The results controller
also drops a preview answer that arrives after Esc.

### Turbo snapshots

On `turbo:before-cache`, the box controller cancels the pending debounce, bumps
the revision, clears the input's value and `value` attribute, and empties the
results frame. The suggest controller clears its input and list and closes the
palette. A snapshot never holds query text or results.

## JavaScript

`app/javascript/querylane/` is plain ES modules and a small `package.json`
(`exports`, peer dependencies). The modules import each other by bare,
extension-qualified names (`querylane/overlay.js`), never by relative path
([ADR 0003](decisions/0003-bare-extension-qualified-imports.md)).
`config/importmap.rb` pins those names for importmap-rails hosts. The modules
never start Stimulus and never change Turbo settings.

| Module | Responsibility |
| --- | --- |
| `index.js` | `registerControllers(application)`; the `querylane_set_query` stream action (a `turbo:before-stream-render` listener) |
| `overlay.js` | `paint(overlay, input, {mask, error})`: colors keys and operators, masks runs, underlines the error range. `textContent` only |
| `controllers/box_controller.js` | The box: debounce, IME composition, too-short hint, revisions and the stale guard, set-query, busy and invalid classes, `/` shortcut, Esc and ↓, Options toggle, snapshot cleanup |
| `controllers/results_controller.js` | Lives on the results frame: ↑/↓/Enter on records, Space preview, "more records" loading once, focus kept across refreshes, selects submit the form, facet "Find…", Enter-clicks for named buttons |
| `controllers/options_controller.js` | The options panel: debounced "Writes" preview, Enter applies, Esc cancels, Reset, Show for masked fields, focus on open |
| `controllers/suggest_controller.js` | Header box and palette: debounced list requests, stale guard, `@github/combobox-nav` for ↑/↓/Enter, Tab completion, Search all and Open options, ⌘K/Ctrl-K, `/`, snapshot cleanup |

Ranges are Ruby character offsets on the server and converted to UTF-16 offsets
at the HTML boundary (`querylane_utf16_range`), which is what the browser
indexes.

## Code map

| Path | What |
| --- | --- |
| `lib/querylane.rb` | Entry point, `configure` |
| `lib/querylane/configuration.rb` | Process-wide settings |
| `lib/querylane/definition.rb` | The DSL, validation, panel layout |
| `lib/querylane/parser.rb`, `ast.rb` | Syntax |
| `lib/querylane/query.rb` | Meaning, validation, localized error messages |
| `lib/querylane/compiler.rb` | Query → text + filters |
| `lib/querylane/filter.rb` | Backend-neutral filter tree |
| `lib/querylane/scope.rb`, `context.rb` | Authorization and request facts |
| `lib/querylane/copy.rb` | Host copy given as a locale key or text |
| `lib/querylane/chips.rb` | Chip labels and masks |
| `lib/querylane/rewriter.rb` | Structural text edits; options panel read/write |
| `lib/querylane/preview.rb` | Masked "Writes" preview |
| `lib/querylane/suggest.rb` | Operator and value completions |
| `lib/querylane/saving.rb` | Saved-search refusal |
| `lib/querylane/group_token.rb` | Encrypted group handles |
| `lib/querylane/request.rb`, `result.rb` | The request and result contracts |
| `lib/querylane/search.rb` | Orchestration: rewrite, states, hooks, counts, saving |
| `lib/querylane/searchers/meilisearch.rb` | The default searcher and filter rendering |
| `lib/querylane/presenter.rb` | Base class for host rows |
| `lib/querylane/controller.rb` | Controller concern and guard |
| `lib/querylane/doctor.rb`, `lib/tasks/querylane.rake` | Index settings check |
| `lib/querylane/engine.rb` | Helper, parameter filtering, assets |
| `app/helpers/querylane/search_helper.rb` | View helpers |
| `app/views/querylane/` | Partials |
| `app/javascript/querylane/` | Stimulus controllers, overlay, stream action |
| `app/assets/stylesheets/querylane.css` | Stylesheet |
| `config/locales/querylane.en.yml` | Copy |
| `spec/dummy/` | The reference host app |

`lib/` is loaded explicitly and is not reloaded. `app/` is reloadable. Host
classes named in a definition are resolved per call, so host reloading works.

## Searcher contract

A searcher responds to:

```ruby
search(definition:, scope:, page:, counts:) # => Response(hits, total, counts, page_limit, backend_calls)
```

- `page` is a `Search::PageRequest` (`compiled, sort, offset, limit`).
- `counts` is a list of `Search::CountRequest` (`key, compiled, attribute,
  value_filters`). The answer's `counts` is `{total: Integer, facet_key =>
  {value => count}}`, or `nil` when counting failed.
- Raise `Querylane::SearchUnavailable` when the backend fails.

Optional: `group_counts(definition:, scope:, attribute:, values:)` → `{value
(down-cased) => count}`, and `max_total_hits` (for the "1,000+" count).

## Decisions

- The box is a native `<input>` with a decorative overlay, not a contenteditable
  editor ([ADR 0001](decisions/0001-search-box-native-input-overlay.md)).
- The query language is parsed on the server by our own StringScanner parser,
  bounded by length, depth and terms
  ([ADR 0002](decisions/0002-own-query-parser.md)).
- Meilisearch 1.13 with the `meilisearch` gem 0.33: one federated call for hits,
  one batched call for exact totals and facet counts. Federation cannot return
  exhaustive totals, which is why counts are a separate batch
  ([spike](spikes/meilisearch-1.13.md)).
- The query text is the only state; facets rewrite it; there is no selections
  parameter.
- One results frame per widget; the box stays outside it; rewrites come back as a
  custom stream action applied in place.
- POST only, `no-store`, filtered params; encrypted group tokens instead of group
  keys in HTML.
- Sensitive options-panel fields are `type="text"` masked with CSS, because a
  password field invites the browser to save an SSN.
- Hosts may compress CSS with SassC, so the stylesheet avoids `min()`, `max()`,
  `clamp()` and space-separated `rgb()`; it uses `font-variant-caps` instead of
  `text-transform` so tests read the source text.
- The JavaScript ships as plain ES modules resolved by the host's bundler through
  Bundler or by importmap-rails; the peers are the host's own copies. The
  modules import each other as `querylane/<file>.js`
  ([ADR 0003](decisions/0003-bare-extension-qualified-imports.md)).
- `meilisearch` is not a runtime dependency. The Meilisearch searcher checks for
  `~> 0.33.0` when it is built.

## Known limits

- The Meilisearch searcher marks filter-facet counts approximate at 100 values,
  Meilisearch's default `maxValuesPerFacet`; a raised setting is not read.
- The doctor needs the Meilisearch searcher, and does not check the group
  attribute, its order attributes or `retrieve`.
- The presenter orders a group's records on the page by comparing the
  `order:` values as text; "more records" and the preview use the searcher's
  sort. The two agree for zero-padded identifiers, not for numbers or dates
  that do not sort as text.
- Saved searches can be created and run, not renamed or deleted: neither the
  store contract nor the Saved popover has those actions.
- A facet's **Find…** box (`search: true`) filters only the values loaded with
  the counts (`top:`); a value outside them cannot be found there.
