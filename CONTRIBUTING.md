# Contributing

Thanks for working on querylane. This page covers setup, the checks every change
must pass, the conventions, and how the docs are organized. Read
[docs/architecture.md](docs/architecture.md) before a larger change.

## Setup

Tools are pinned in `mise.toml` (Ruby 3.3, Node 22, FracturedJSON).

```sh
mise install
bundle install
npm install                       # Turbo, Stimulus, combobox-nav, Playwright (dev only)
npx playwright install chromium   # for system specs
```

Most specs need a Meilisearch 1.13+ server:

```sh
export MEILISEARCH_URL=http://localhost:7700
export MEILISEARCH_API_KEY=your-key
```

The suite drops and recreates the indexes `querylane_spec_staff` and
`querylane_spec_contractors` on that server.

## Running the checks

```sh
bundle exec rspec                 # everything; :meilisearch examples skip without a server
bundle exec rspec spec/querylane  # unit specs only
bin/lint                          # StandardRB, then FracturedJSON on tracked JSON files
bin/lint fix                      # apply StandardRB fixes and reformat JSON
bundle exec rake                  # the suite and StandardRB, as CI runs it
```

Run them through mise if your shell does not activate it:
`mise exec -- bundle exec rspec`, `mise exec -- bin/lint`.

`bin/lint` checks JSON files known to git (`git ls-files`), outside `spec/dummy`.

## The dummy app

`spec/dummy` is the reference host: a definition (`app/searches/dummy_search.rb`),
a presenter, a controller using every controller call, an in-memory saved-search
store, the header box and palette (`/elsewhere`), and an import-map layout that
serves the gem's JavaScript straight from `app/javascript`. Request and system
specs run against it. Keep it working and keep it showing every feature: it is
also the example the guides quote.

## Conventions

- **Style:** StandardRB. Do not add a `.rubocop.yml`.
- **One concern per file.** Public API first, then private helpers.
- **Header comments** on every class and module: what it is for and how it fits
  the flow. Document public methods with YARD (`@param`, `@return`).
- **Ruby decides, partials draw.** No markup built in Ruby; presenters and
  helpers return data or render partials.
- **CSS** must pass SassC compressors: no `min()`, `max()`, `clamp()` or
  space-separated `rgb()`. Use `font-variant-caps`, never `text-transform`. Keep
  `[hidden]` winning over display rules.
- **JavaScript** is plain ES modules that import each other as
  `querylane/<file>.js`, never by relative path. Never start
  Stimulus or change Turbo settings from the gem. Use `textContent`, never
  `innerHTML` with data.
- **Privacy rules are invariants.** Query text travels by POST, responses are
  `no-store`, sensitive values are masked wherever they are shown, group keys
  never reach HTML, saving refuses sensitive terms. A change that weakens one
  needs a decision record.
- **Tests:** every behavior gets a spec at the right layer: unit
  (`spec/querylane/`), integration against Meilisearch (`spec/integration/`),
  request (`spec/requests/`) or browser (`spec/system/`).
- **Changelog:** add a line under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md)
  for anything a host would notice.
- **CI:** GitHub Actions (`.github/workflows/ci.yml`): `rake` on Ruby 3.3, 3.4
  and 4.0 against Meilisearch 1.13 and headless Chromium. Actions are pinned to
  commit SHAs. FracturedJSON is not run in CI; run `bin/lint` before pushing.
- **Security:** no secrets in the repo; see [SECURITY.md](SECURITY.md).

## Releasing

Releases go to rubygems.org from GitHub Actions with
[trusted publishing](https://guides.rubygems.org/trusted-publishing/) (no API
key) and a Sigstore attestation (`.github/workflows/release.yml`, in the
`rubygems` environment).

Before the first release, an owner of the gem adds a pending trusted publisher
on rubygems.org (Profile → Trusted publishers): gem `querylane`, repository
owner `clearstackio`, repository `querylane`, workflow `release.yml`,
environment `rubygems`. After the first push it becomes the gem's trusted
publisher.

1. Update `VERSION` in `lib/querylane/version.rb` and run `bundle install` so
   `Gemfile.lock` follows.
2. Move the `[Unreleased]` entries in `CHANGELOG.md` under the new version and
   date, and update the compare links at the bottom.
3. Commit, then tag and push: `git tag v0.1.0 && git push origin master v0.1.0`.

The workflow runs the full CI suite on the tagged commit (Meilisearch and
Chromium included), checks the tag matches `VERSION`, then builds, pushes and
attests the gem. A failing suite publishes nothing.

## Documentation

| Where | What |
| --- | --- |
| [README.md](README.md) | The front door: pitch, install, quick start |
| [docs/guides/](docs/README.md) | One guide per topic, for people using the gem |
| [docs/architecture.md](docs/architecture.md) | How the gem works, for contributors |
| [docs/decisions/](docs/decisions/README.md) | Decision records (ADRs) |
| [docs/spikes/](docs/spikes/meilisearch-1.13.md) | Evidence from backend experiments |
| [AGENTS.md](AGENTS.md) | Instructions for coding agents |

When you change behavior, update the guide that describes it in the same change.
Examples in the guides should match the dummy app or a spec. Record a decision
that is hard to reverse as a new ADR in `docs/decisions/` and list it in its
README.
