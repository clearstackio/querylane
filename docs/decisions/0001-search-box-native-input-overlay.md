# 0001 — The search box is a native `<input>` with a decorative overlay

**Status:** Accepted · **Date:** 2026-10-12 · **Deciders:** Ajaya Agrawalla (owner), reviewed with codex (two rounds)

## Context

The box must colour operator keys as they are typed, visually mask digit runs
read as member IDs, underline the exact range of a server-reported error,
later suggest operators and people at the caret (header dropdown, Cmd-K
palette) and sync with an options panel. It must also keep native caret,
selection, undo and IME behaviour, submit as a real form field through a
Turbo POST, and work with Capybara/Black Box `fill_in "Search Text"`.

## Decision

Use a native, labelled `<input>` as the only source of the value, with an
`aria-hidden`, pointer-events-free overlay behind transparent input text that
paints the colours, masks and error underline. One Stimulus controller owns
it. Add `@github/combobox-nav` (ARIA 1.2 listbox keyboard navigation) when
suggestions ship; M1 has none.

## Consequences

- Native editing, forms, autofill-off and test drivers keep working.
- We own the overlay: identical font metrics (monospace), padding, scroll
  sync, selection colour, placeholder colour, forced-colours fallback, and
  digit-width-preserving masks. Masking is visual only; the input still holds
  the raw value.
- Programmatic edits (panel, completion) need explicit undo handling later.

## Alternatives considered

- **CodeMirror 6 single-line** — the most complete library (highlighting,
  completion, decorations, transactions); rejected: not an `<input>` (hidden
  mirror field, `fill_in` breaks), editor-managed undo/IME, largest footprint,
  masking through widgets complicates caret and composition.
- **Tagify mix mode** — inline pills; rejected: contenteditable, pills change
  editing semantics, Paper draws coloured text with chips below.
- **textcomplete** — caret completion for textarea; no highlighting/masking,
  no documented input adapter.
- **@github/auto-complete-element**, **Algolia Autocomplete** — suggestion
  dropdowns only; may complement combobox-nav later.
- **Choices.js / Tom Select** — select widgets; candidates for options-panel
  fields, not for the box.
