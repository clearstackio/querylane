# 0002 — Parse the query language on the server with our own parser

**Status:** Accepted · **Date:** 2026-10-12 · **Deciders:** Ajaya Agrawalla (owner), reviewed with codex

## Context

The language is Gmail-style: implicit AND, `OR` (binding tighter), `-`/`NOT`,
parentheses, `key:value`, quotes. Meaning, chips, errors and the options
panel must come from one parser ("one parser, one truth"), with exact source
ranges for errors and chip removal, bounded input, and masking of sensitive
values.

## Decision

A hand-written Ruby `StringScanner` recursive-descent parser in the gem,
bounded (256 characters, depth 3, 20 terms), producing an AST with ranges.
The browser never parses; it only colours characters for display.

## Consequences

- Small grammar fully under our control; precise errors and "did you mean".
- We own quote escapes, Unicode offsets (converted to UTF-16 at the HTML
  boundary), precedence and malformed-input tests.
- If the grammar grows (round-trip editing, richer boolean), move to Parslet.

## Alternatives considered

Re-examined 2026-10-12 at the owner's request ("aren't there parser engines
we can use?"), with codex reading the actual parser. Verdict: keep it; an
engine would replace syntax recognition only, while AST ranges, bounds and
friendly diagnostics (the parts that matter) stay ours either way.

| Engine | Fit |
| --- | --- |
| Parslet (PEG, 2.0.0, Feb 2020) | Best alternative: readable grammar, `Slice#offset` is a character offset; failure trees are generic, so friendly messages need a second pass that duplicates the lexer |
| Treetop (PEG, 1.6.18, Nov 2025) | Readable external grammar; same diagnostics gap; generated-code conventions |
| Citrus (PEG, 3.0.2, 2015) | Byte offsets; stale |
| Racc (LALR, bundled gem since Ruby 3.3) | Best maintained; still needs our lexer and actions plus a `.y` compile step |
| Raabro, rly | No advantage for this grammar |

Earlier comparison:

- **Parslet** (Ruby PEG toolkit) — the strongest alternative; deferred until
  the grammar justifies a dependency and DSL.
- **liqe** (Lucene-like, TypeScript, AST + serializer) — Lucene-flavoured and
  a second runtime for an authoritative server parse.
- **search-query-parser** (JS), **keyword_search**, **querylicious** (Ruby) —
  key:value and negation only; no OR/parentheses; some unmaintained.
