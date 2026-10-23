# Changelog

All notable changes to querylane are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, a minor version may
change public APIs; each entry says how.

## [Unreleased]

### Added

- `config.logger`: querylane logs why a search was unavailable (Meilisearch
  unreachable, timed out, or an API error such as a missing index). API
  errors are logged by code, type and HTTP status only, never their message,
  which can echo the filter; connection errors lose any URL credentials and
  query string. The default logger writes to standard output; a Rails host
  passes `Rails.logger`.
- `p.row ... hint:, placeholder:` on options-panel rows: a line under the row
  (its fields' `aria-describedby`) and a placeholder for its empty inputs (a
  masked field's "In the box: …" still wins). `placeholder:` on a flags or
  options row raises.
- `d.filter ... invalid:`: a second sentence for the bad-value error.
- `d.filter ... as_words: true`: when nothing matches, the empty state offers
  "Search "smiht" as part of a name" (`querylane.states.as_words`, request
  param `as_words=<chip index>`, `Rewriter.as_words`), which replaces the
  filter term with its typed value as plain words. Refused on a sensitive
  filter.
- `d.filter ... display_value: :typed`: chips and the options panel show the
  value as typed, and the panel writes it back as typed; the search still
  uses the normalized value. Needs `mask: :none`.
- `hint:`, `placeholder:` and `invalid:` take a locale key (a Symbol or a
  dotted String) or plain text (`Querylane::Copy`), translated when shown.

### Changed

- Development Ruby 3.3.13 (from 3.3.10): the lowest supported series' release
  with the Onigmo regexp fixes (CVE-2026-89078, CVE-2026-93577,
  CVE-2026-97229, CVE-2026-110264). `required_ruby_version` and the CI
  matrix are unchanged.
- Every query error is a translation under `querylane.errors.*` (syntax,
  limits, unknown and parked operators, bad filter and flag values, names in
  OR, NOT and parentheses, one text operator). The English text is unchanged
  and stays the default (`Querylane::Query::MESSAGES`).
- With no filters declared, the one-text-operator error no longer ends in
  "or combine with ."; it reads "Search name or id one at a time."
- `Definition::FilterOperator` gains `invalid`, `as_words` and
  `display_value`, `Definition::PanelRow` gains `hint` and `placeholder`, and
  `Chips::Chip` gains `as_words`. Each new member has a default, so code that
  builds these structs with the earlier members, by position or keyword,
  still works.

- Every partial declares its locals on its first line (Rails strict locals,
  `<%# locals: (...) -%>`). A host override must keep the line, and a render
  with other locals now raises. `_help` takes `popover_id: nil` instead of
  reading `local_assigns`.
- Controls follow one hierarchy (theming guide, "Bootstrap"): the box's
  Search and the options panel's Search are outline buttons
  (`btn-outline-primary`); Open and View are Go links (`.ql-go`, still a
  button that posts); the empty state's actions and the panel's Cancel are
  quiet links (`.ql-link`). `Presenter::Action#style` no longer changes the
  look.
- No Bootstrap utility classes: `.ql-visually-hidden` replaces
  `visually-hidden`, `.ql-open-form` replaces `d-inline`, and `.ql-pager`
  sets its own margin instead of `mb-0`.
- The search box and the suggestion box sit in a `<search>` landmark
  (`.ql-search`) instead of a form with `role="search"`.
- The facet column's accessible name comes from `querylane.facets.label`.

### Fixed

- Space on a record right after a new answer drew its rows opens the preview.
  The preview state was reset on `turbo:frame-render`, which Turbo fires a few
  repaints after the rows are in, so the preview's answer was dropped as if
  Esc had closed it. It is now reset when the new, empty preview frame
  connects.

## [0.1.0] - 2026-10-20

The first release.

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

[Unreleased]: https://github.com/clearstackio/querylane/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/clearstackio/querylane/releases/tag/v0.1.0
