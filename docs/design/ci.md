<!-- cspell:words MEILISEARCH Meilisearch Querylane Sigstore querylane querylane's rubygems -->

# CI design

querylane runs on GitHub Actions. To run or fix it, see
[CI operations](../ops/ci.md).

## `ci.yml`

Runs on pushes to `master`, pull requests, manual dispatch, and calls from
`release.yml`. A newer run on the same ref cancels the older one.

One job, `test`, on `ubuntu-latest`, for Ruby 3.3, 3.4 and 4.0 with `fail-fast`
off. It has a Meilisearch 1.13 service container, so no example skips. Steps:
checkout, Ruby with `bundler-cache`, `npm ci`, Playwright's Chromium, wait for
Meilisearch, then `bundle exec rake` (the suite and StandardRB). The Bundler cache
is the only cache. FracturedJSON is not run in CI.

## `release.yml`

Runs on `v*` tags. `ci` calls `ci.yml` on the tagged commit; `release` needs it.
`release` runs in the `rubygems` environment on the Ruby in `.ruby-version`, checks
the tag equals `v` plus `Querylane::VERSION`, and publishes with
`rubygems/release-gem` through trusted publishing (OIDC, no API key) and a Sigstore
attestation.

## Security

Actions are pinned to commit SHAs, checkouts do not persist credentials, and
`permissions` are least privilege: `contents: read` everywhere, plus `id-token:
write` on `release`.
