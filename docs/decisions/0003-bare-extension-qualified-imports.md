# 0003 — The modules import each other as `querylane/<file>.js`

**Status:** Accepted · **Date:** 2026-10-20 · **Deciders:** Ajaya Agrawalla (owner)

## Context

The same files in `app/javascript/querylane/` must load in every way a host
serves JavaScript: importmap-rails on Propshaft or Sprockets, a webpack or
esbuild alias, the directory installed as an npm package, and a hand-written
import map (the dummy app).

Relative imports (`./controllers/box_controller.js`) break under
importmap-rails: the files are served at digested URLs, so a relative import
asks for an undigested path that Propshaft does not serve. Bare names without
an extension (`querylane/overlay`) work in an import map and under a webpack
alias, but not when the directory is resolved as a package: its `exports`
cannot map an extension-less subpath without one entry per file, and a
hand-written import map needs one entry per module.

## Decision

The modules import each other by bare, extension-qualified names:
`querylane/overlay.js`, `querylane/controllers/box_controller.js`.

- `config/importmap.rb` pins `querylane` (index.js) and every other file
  under its own name, generated from the directory, with `preload: false`.
- `package.json` exports `"."` and `"./*"`.
- A hand-written import map needs `"querylane"` and one `"querylane/"` prefix.

## Consequences

- One spelling works under importmap-rails, webpack and esbuild aliases, npm
  package resolution and plain import maps; a new module needs no map edits.
- The import names are public: renaming or moving a module file is a breaking
  change for hosts that pin or alias it.
- `spec/querylane/importmap_spec.rb` checks every import is either a peer or a
  pinned `querylane/<file>.js` name, and draws the map with importmap-rails.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Relative `.js` imports | Miss importmap-rails' digested URLs |
| Bare names without an extension | Fail npm package resolution; one import map entry per module |
| Ship a prebuilt bundle | Hosts lose their own copies of Turbo and Stimulus, which the stream action needs |
