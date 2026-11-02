<!-- cspell:words MEILISEARCH Meilisearch Querylane Sigstore querylane querylane's rubygems -->

# CI operations

How to run and fix querylane's CI. For how it works, see
[CI design](../design/ci.md). Release steps are in
[CONTRIBUTING](../../CONTRIBUTING.md#releasing).

## Run what CI runs

```sh
mise exec -- bundle exec rake   # needs MEILISEARCH_URL and MEILISEARCH_API_KEY
mise exec -- bin/lint           # adds FracturedJSON, which CI does not run
```

## Retrigger

```sh
gh run list --workflow ci.yml
gh run view <run-id> --log-failed
gh run rerun <run-id> --failed
gh workflow run ci.yml --ref <branch>
```

## Fix a failure

| Symptom | Fix |
| --- | --- |
| One Ruby fails | Run `rake` on that version; the others still finish |
| `Wait for Meilisearch` times out | The service container did not start in 60 seconds; rerun |
| `Tag vX does not match version Y` | Fix `lib/querylane/version.rb` or the tag, then push a matching tag |
| `release` fails to publish | Check the trusted publisher on rubygems.org names `release.yml` and `rubygems` |
