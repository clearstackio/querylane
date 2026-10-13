# querylane — instructions for coding agents

querylane is a Rails 8.1 engine (Ruby ≥ 3.3) that gives a host app a Gmail-style
search box with a small query language over Meilisearch 1.13 indexes, plus
server-rendered widgets: chips, facets, toolbar and pager, grouped rows from a
host Presenter, an options panel, "more records", a preview, a header box and
⌘K palette, saved searches. Hotwire (Turbo Frames, Stimulus 3), Bootstrap 5
classes, `@github/combobox-nav`.

This file is the only agent instruction file for the repo. Do not add
tool-specific instruction files.

## Read first

- [docs/architecture.md](docs/architecture.md): request flow, frames, revisions,
  JS controllers, decisions.
- [docs/guides/](docs/README.md): the public behavior, one guide per topic.
- [CONTRIBUTING.md](CONTRIBUTING.md): setup and checks.

## Layout

| Path | What |
| --- | --- |
| `lib/querylane/definition.rb` | DSL and validation |
| `lib/querylane/{parser,ast,query}.rb` | Syntax, meaning, errors |
| `lib/querylane/{compiler,filter,scope,context}.rb` | Filters and authorization |
| `lib/querylane/{chips,rewriter,preview,suggest,saving,group_token}.rb` | Query-text features |
| `lib/querylane/{request,result,search}.rb` | Contracts and orchestration |
| `lib/querylane/searchers/meilisearch.rb` | Default searcher |
| `lib/querylane/{presenter,controller,engine,doctor}.rb` | Host-facing pieces |
| `app/helpers`, `app/views/querylane` | Helpers and partials |
| `app/javascript/querylane` | Stimulus controllers, overlay, stream action |
| `app/assets/stylesheets/querylane.css` | Stylesheet (`--ql-*` properties) |
| `config/locales/querylane.en.yml` | Copy |
| `spec/dummy` | Reference host app |
| `spec/{querylane,integration,requests,system}` | Unit, Meilisearch, request, browser specs |

## Commands

```sh
mise install && bundle install && npm install && npx playwright install chromium
mise exec -- bundle exec rspec                  # needs MEILISEARCH_URL / MEILISEARCH_API_KEY
mise exec -- bundle exec rspec spec/querylane   # unit only, no backend
mise exec -- bundle exec rspec spec/requests/search_spec.rb:42
mise exec -- bin/lint                           # StandardRB + FracturedJSON
mise exec -- bin/lint fix
mise exec -- bundle exec rake                   # suite + StandardRB, as CI runs it
```

The suite recreates the `querylane_spec_*` indexes on the configured Meilisearch.
Run focused examples while iterating.

## Rules

### Code

- StandardRB formats Ruby; no `.rubocop.yml`.
- One concern per file. Public API first, private helpers after.
- A header comment on every class and module (purpose, place in the flow).
  Document public methods with YARD.
- Ruby decides, partials draw. Never build HTML in Ruby.
- Reference host classes by name and resolve per call (reload safety).
- No registries or abstract base classes for seams; one default each.

### CSS and JavaScript

- No CSS `min()`, `max()`, `clamp()` or space-separated `rgb()`: hosts compress
  with SassC.
- No `text-transform`; use `font-variant-caps`. Tests read the source text.
- `[hidden]` must win over every display rule inside the widgets.
- ES modules that import each other as `querylane/<file>.js`: bare and
  extension-qualified, never relative (ADR 0003). Never start Stimulus or
  change Turbo settings. Write DOM text with `textContent`.
- Keep ids, `data-*` hooks, `form=` attributes and button names stable; the
  controllers and the server depend on them.

### Privacy invariants (never weaken without an ADR)

- Query text travels by POST only; the guard checks the URL query string.
- Every querylane response is `Cache-Control: no-store`.
- `search_query` and `compose` are filtered from logs; instrumentation never
  carries query text.
- Sensitive operators are masked in chips, errors, the options panel, the
  preview and suggestions.
- Group tokens are encrypted and expiring; group keys and member IDs never reach
  HTML.
- Saving refuses sensitive terms, typed or interpreted, at any depth.
- Every query ANDs the scope; no scope, a failing hook or a backend error fails
  closed.

### Tests and docs

- Every behavior gets a spec: unit, integration, request or system.
- Keep the dummy app working; it is the reference host and the guides quote it.
- Update the guide for any behavior you change, and add a CHANGELOG line under
  `[Unreleased]`.
- Hard-to-reverse decisions get an ADR in `docs/decisions/`.

### Release and distribution

- SemVer, with a Keep a Changelog CHANGELOG. Steps: CONTRIBUTING.md, Releasing.
- Releases go to rubygems.org from GitHub Actions only (`release.yml`, trusted
  publishing, Sigstore attestation); never a manual `gem push`.
- Third-party actions are pinned to a commit SHA, with least-privilege
  `permissions`.
- The source lives at `https://github.com/clearstackio/querylane`. Hosts
  consume a release from rubygems.org; to try unreleased work, use `git:` plus
  `bundle config local.querylane <path>`, never a committed `path:` dependency.

### Boundaries

- Never edit a host app from this repo.
- Do not commit, push or create branches unless asked.
