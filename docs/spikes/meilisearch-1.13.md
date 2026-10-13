# Spike: Meilisearch 1.13.3 + meilisearch-ruby 0.33.0 (2026-10-12)

Run against EBA's development indexes (employees, did_employees,
ebmr_employees) through `Meilisearch::Client#multi_search`.

| Capability | Result | Querylane use |
| --- | --- | --- |
| Federated multi-search, `federation: {offset, limit}` | Works; response has `hits`, `estimatedTotalHits`; each hit carries `_federation.indexUid`, `queriesPosition`, `weightedRankingScore` | Hits for a page |
| Federation `page`/`hitsPerPage` (exhaustive totals) | **Not supported** (400: expected `limit`, `offset`, `facetsByIndex`, `mergeFacets`) | Exact totals come from the count batch instead |
| Federated sort (same `sort` on every query) | Works; global order across indexes | Name / effective / policy sorts |
| `facetsByIndex` + `mergeFacets` | Works | Not used (facet bases differ per facet; see below) |
| Non-federated multi-search, `page: 1, hits_per_page: 0` + `facets` | Works; exact `totalHits` and `facetDistribution` per index | Exact totals and all facet counts in one HTTP call |
| `showRankingScoreDetails` | Works; per hit `_rankingScoreDetails` with `typo`, `proximity`, `words`, … | Match-note evidence ("close spelling") |
| Custom highlight tags (`\u0001`/`\u0002`) | Works in `_formatted` | Escape, then `<mark>` |
| `IS NULL` / `NOT EXISTS` filters | Accepted | Unknown status |
| `attributesToSearchOn: [memberid]`, prefix | Matched in the spike; see the correction below: numeric prefixes do not match | `id:` |
| `typoTolerance.disableOnAttributes` | Index setting; empty on dev DID index until reindexed | `querylane:doctor` checks it |
| Ruby gem keys | Top-level keys must be snake_case (`index_uid`, `hits_per_page`, …) or the gem warns | Searcher sends snake_case |

Decision: one federated call for the page of hits, one batched
non-federated call for exact totals and facet counts (counts per flag value
via `hits_per_page: 0` queries; filter facets via `facets`).

## Correction (2026-10-12): numbers do not prefix-match

Checked later against EBA's indexes: a query for the first digits of a number
(`1234` for policy `123456`, the first five digits of a member ID) finds
nothing, on attributes with typo tolerance disabled; the whole number matches.
So "starts with" on numeric identifiers cannot rely on text search. EBA
indexes the leading 3 to 9 characters as a filterable array and matches them
exactly (`memberid_prefixes`, `number_prefixes`).
