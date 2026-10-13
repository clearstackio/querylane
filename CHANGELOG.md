# Changelog

All notable changes to querylane are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, a minor version may
change public APIs; each entry says how.

## [Unreleased]

The first release, planned as 0.1.0.

### Added

- importmap-rails support (Propshaft or Sprockets): `config/importmap.rb` pins
  `querylane` and each module by its file name (`querylane/overlay.js`,
  `querylane/controllers/*.js`), none preloaded; the engine adds
  `app/javascript` to the asset load path and, when importmap-rails is loaded,
  appends the gem's map to `config.importmap.paths` and the modules to
  `config.importmap.cache_sweepers`, but only when the host has its own
  `config/importmap.rb`. Hosts pin `@hotwired/stimulus` and
  `@github/combobox-nav`. The `querylane.css` precompile entry is added only
  under Sprockets.
- The `querylane_set_query` stream action is handled through
  `turbo:before-stream-render` instead of `StreamActions`, so querylane never
  imports `@hotwired/turbo` and works with turbo-rails' bundled Turbo.
- The modules import each other as `querylane/<file>.js` instead of by relative
  path (ADR 0003), so one set of files serves importmap-rails, webpack and
  esbuild aliases, and the npm package (`package.json` now exports `./*`).
  Hand-written import maps need `querylane` and one `querylane/` prefix entry.

- Query language: words, `key:value` operators, quoted phrases with `\"` and `\\`
  escapes, implicit AND, `OR` (binding tighter than AND), `-` and `NOT`,
  parentheses. Bounded by length, nesting depth and term count. Errors carry a
  character range, a "did you mean" suggestion and a one-click **Fix it**.
- `Querylane::Definition.build` DSL: `index`, `text`, `filter` (normalize,
  format, sensitive, masks `:none`/`:all`/`:last4`/`:count`), `flags` (attribute
  or per-index rules, aliases), `facet` (flag or filter, value subsets, `top`,
  `show`, "Find…" search), `sort`, `per`, `retrieve`, `highlight`,
  `interpreter` (with "… instead" alternatives), `parked`, `min_text_length`,
  `group` (`valid`, `limit`, `order`), `saved`, `option`, `panel`, `example` and
  `hook`. Declarations are validated at build time.
- Required `Querylane::Scope` with a permission filter per index;
  `Scope.unrestricted` and `Scope.denied`. Backend-neutral `Querylane::Filter`
  (`eq`, `in`, `null`, `missing`, `and`, `or`, `not`, `everything`, `nothing`,
  `raw`).
- Query-filter and results hooks with a `Querylane::Context`; results hooks
  declare `:preserving` or `:changing` cardinality. Hooks fail closed.
- Meilisearch searcher (Meilisearch 1.13+, `meilisearch` gem `~> 0.33.0`):
  federated hits across indexes, one batched call for exact totals and
  disjunctive facet counts, per-group record counts, highlight markers. Fails
  closed with an `:unavailable` state; a failed count batch keeps the hits.
- `rake querylane:doctor[Definition]` checks index settings.
- `Querylane::Controller`: `querylane_search`, `querylane_preview`,
  `querylane_related`, `querylane_suggest` and `querylane_frame?`, with a guard
  that refuses query text in a GET URL and sends `Cache-Control: no-store`.
- View helpers and partials (Bootstrap 5 classes): `querylane_form` (native
  input with a colored, masking overlay; optional help text),
  `querylane_results` (chips, error with Fix it, facets, toolbar, pager, grouped
  rows, footer), `querylane_suggest_box` (header dropdown or ⌘K / Ctrl-K
  palette) with `querylane_suggestions`, and `querylane_related` ("more records"
  and the Space preview).
- States: first load with examples, too short, empty (widen, drop, relax),
  invalid, unavailable, denied.
- Options panel that reads the query into fields and writes it back, with a live
  masked "Writes" preview.
- Saved searches through a host store (`all`, `create`, `use` with `context:`);
  queries with sensitive terms, typed or interpreted, are refused.
- `Querylane::Presenter` base class for host rows: columns, cells, status,
  flags, Open action or reason (with "+N more"), group titles, suggestions.
- Encrypted, expiring group tokens; group keys never reach the page.
- Stimulus controllers (`querylane--box`, `--results`, `--options`,
  `--suggest`) and the `querylane_set_query` Turbo Stream action, registered with
  `registerControllers(application)`. Revisions drop stale responses; Turbo
  snapshots never keep query text.
- `querylane.css` themed by `--ql-*` custom properties; safe for SassC
  compressors.
- English translations under `querylane.*`.
- `search.querylane` and `saved_search_failed.querylane` instrumentation, without
  query text. The query parameter and `compose` are filtered from logs.

[Unreleased]: https://github.com/clearstackio/querylane/commits/master
