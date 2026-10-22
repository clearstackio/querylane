# Widgets

Every widget is server-rendered by the engine's partials and driven by four
Stimulus controllers. A widget has an **id** (for example `:people`). The id
names its form, frames and elements:

| Element | Id |
| --- | --- |
| Search form | `people-form` |
| Box container | `people-box` |
| Text input | `people-query` (change it with `input_id:`) |
| Results frame | `people-results` |
| Options panel "Writes" frame | `people-writes` |
| Preview frame | `people-preview` |
| "More records" frame of one group | `people-related-<16 hex>` |
| Options panel | `people-options` |
| Saved searches popover | `people-saved` |
| Error line | `people-error` |

Every control on the page is a submit button or field of the one search form
(through the HTML `form=` attribute), so every request carries the live box
text. All requests are POSTs.

## Search form and box

```erb
<%= querylane_form @result, id: :people, url: search_path %>
```

| Option | Default | Meaning |
| --- | --- | --- |
| `id:` | required | Widget id |
| `url:` | required | The POST endpoint |
| `input_id:` | `"#{id}-query"` | Id of the `<input>` (keep test hooks stable) |
| `label:` | `querylane.box.label` | Accessible label (visually hidden) |
| `placeholder:` | `querylane.box.placeholder` | |
| `mask:` | `nil` | A JavaScript regexp source. Letters and digits in matching text are drawn as dots, for example `'\b\d{9}\b'` |
| `button_id:` | `nil` | Id of the Search button |
| `options:` | `true` | Show the Options button |
| `help:` | `nil` | Help text under the box. The input's `aria-describedby` points at it |
| block | | Extra controls, placed after the clear button |

The box is a native `<input>` with a decorative overlay behind its transparent
text ([ADR 0001](../decisions/0001-search-box-native-input-overlay.md)). The
overlay colors operator keys and `OR`/`NOT`/`-`/parentheses, shows masked runs as
dots and underlines the range of a server error. Masking is visual only: the
input still holds what was typed.

Typing submits the form into the results frame after `debounce_ms` (300 ms).
Enter searches at once. While the frame loads, the box shows "Searching…".
Words too short to search (see `min_text_length`) send nothing: a hint appears
and the last results stay.

The box also has:

- **×** clears the box and searches.
- **Saved** (only with `d.saved`) opens the saved searches popover. Its star is
  filled (`aria-pressed="true"`) while the box holds one of the user's saved
  searches.
- **Options** opens the options panel. While the panel is open, Options closes
  it (a plain search). Its `aria-expanded` follows the panel.

The box element can be styled while busy (`.ql-box-busy`) and invalid
(`.ql-box-invalid`).

## Results frame

```erb
<%= querylane_results result, id: :people, presenter: PersonPresenter %>
```

| Option | Meaning |
| --- | --- |
| `id:` | Widget id |
| `presenter:` | A `Querylane::Presenter` subclass; the gem draws grouped rows |
| block | Instead of a presenter: your own rows for `result.hits` |
| `info_id:` | Id of the "Showing 1 to 25 of 80 entries" line |
| `per_id:` | Id of the page-size select |
| `first_load:` | HTML shown instead of the default first-load screen |

The frame holds, top to bottom:

1. A set-query stream when the server rewrote the query (see below).
2. The error line (`role="alert"`) with **Fix it** when there is a correction.
3. A notice from saved searches ("Search saved.").
4. The saved searches popover.
5. The chips.
6. The options panel, when open. Everything under it is `inert` meanwhile.
7. The body for the current state, with facets, toolbar, rows and footer.

The frame carries `data-revision`. A response older than what the box has sent
since is dropped ([Architecture](../architecture.md#revisions-and-stale-responses)).

### States

| `result.state` | Shown |
| --- | --- |
| `:first_load` | "Who are you looking for?" with the definition's examples |
| `:short` | "Type at least N letters of a name, or add an operator." |
| `:ok` | Facets, toolbar, rows, footer |
| `:empty` | "Nothing matches …" with buttons to widen a facet, drop a chip and allow fewer name matches, and, for a filter declared `as_words: true`, "Search "smiht" as part of a name" (posts `as_words=<chip index>`; the box gets the typed value as plain words in place of the filter term) |
| `:invalid` | Only the error line; nothing was searched |
| `:unavailable` | "Search is not answering right now." with Try again |
| `:denied` | "No results: your access could not be checked." |

Override `querylane/_first_load`, `_empty`, `_unavailable` or `_denied` to change
a state ([Theming](theming.md#overriding-partials)).

### Chips

"Searching for" lists what the query means: one chip for all name words and one
per top-level term. Sensitive values are masked. Each chip has × (`remove=<chip
index>`). An interpreted term can have "… instead" buttons
(`instead=<chip>.<alternative>`). The row ends with **Syntax help** (a popover
built from the definition) and **Clear** (`clear=1`).

While the user types, the chips dim and × is disabled until the new answer
arrives.

### Facets

Each value is a submit button with checkbox semantics (`role="checkbox"`,
`aria-checked`). It sends `toggle=<facet>:<value>`; the server rewrites the query
and sends the new text back. Only values that are ticked or have a count show.
Values past `show` are hidden; with `search: true` a "Find…" box filters the
loaded values in the browser. "Counts unavailable" shows when counting failed;
the hits are kept.

### Toolbar and pager

The count reads "80 records", "about 80 records" (counts failed, so the total is
the backend's estimate) or "1,000+ records" (the backend's `maxTotalHits` cap).
"Copies of the same record are shown once" appears when a results hook merged
hits.

Sort and page-size selects submit the form (`sort=`, `per=`). The pager shows
Previous, up to five page numbers and Next (`page=`). It stops at the backend's
cap. Any change other than paging returns to page 1.

### Rows

With a presenter, rows are drawn in groups: a title, optional subtitle and note,
then one line per record in lanes (your columns, a status badge, flags, and the
Open button or a reason). See [Presenter](presenter.md).

### Footer

"Showing x to y of z entries" and a key legend.

## More records

A group whose records are not all on the page gets "N more records for this
person" (a `<details>`). Opening it the first time posts `group=<token>` into the
group's `people-related-…` frame. The answer lists the records the page did not
show, in the group's order, any status, within the user's scope. "Hide" closes it.

The token is an encrypted, expiring handle; the group's key (for example a
member ID) never reaches the page ([Security](security.md#group-tokens)).

Serve it with `querylane_related` in the controller and helper
([Controller](controller.md#querylane_related)).

## Preview

Space on a focused record opens a preview of every record in its group, posted
as `group=<token>` into the `people-preview` frame. ↑ and ↓ move to the next
record and the preview follows. Esc or "Close" closes it and returns focus to
the record. A preview that arrives after Esc is dropped.

## Options panel

Options posts `options=1`. The panel opens inside the results frame, filled from
the box: each field shows the values the query has for its operator, checkboxes
for flags and options. Parts no field can show are listed as "Kept as typed".

- Editing a field posts `compose_preview=1` with `compose[...]` into the
  `people-writes` frame after the debounce. The "Writes" line shows the query the
  fields would write, with sensitive values masked. No search runs. Serve it with
  `querylane_preview` ([Controller](controller.md#querylane_preview)).
- **Search** (or Enter in a field) posts `compose_submit=1` with the fields. The
  server composes the new text, the panel closes, and the box updates.
- **Cancel** (or Esc) runs a plain search and closes the panel.
- **Reset fields** empties every field.
- A masked field starts empty, shows the masked terms it leaves in the box as its
  placeholder, hides what is typed, and has a **Show** button.
- A row declared with `placeholder:` shows it in its empty inputs (a masked
  field's "In the box: …" placeholder wins). A row declared with `hint:` shows a
  line under its fields, which describes them (`aria-describedby`). See
  [Definition](definition.md#the-options-panel).

Opening the panel focuses its first field. The panel needs a valid query; with
an invalid one it does not open.

## Saved searches

With `d.saved`, the **Saved** button opens a popover: a name field and Save
(`save_search=1`, `saved_name=`), then the user's saved searches. Choosing one
posts `saved=<id>`; the server replaces the box with its text. A query holding a
sensitive value cannot be saved; the popover says why and what could be saved
instead. See [Saved searches](saved-searches.md).

## Suggest box: header and palette

A box for any page that suggests operators and people, and hands off to the
search page.

```erb
<%= querylane_suggest_box id: :find, url: suggest_path, search_url: search_path %>
<%= querylane_suggest_box id: :palette, url: suggest_path, search_url: search_path, mode: :palette %>
```

| Option | Default | Meaning |
| --- | --- | --- |
| `id:` | required | Widget id; the list frame is `"#{id}-list"` |
| `url:` | required | POST endpoint for suggestions |
| `search_url:` | required | The full search page (POST) |
| `mode:` | `:header` | `:header` (inline dropdown) or `:palette` (a `<dialog>`) |
| `trigger:` | `true` | Palette only: show a button that opens it |
| `label:`, `placeholder:` | `querylane.suggest.*` | |

Typing posts the text into the list frame (debounced, older answers dropped).
The list has up to three groups:

- **Operators**: completions for the last word. `pol` suggests `policy:`, `is:a`
  suggests `is:active`. The rest of the text is what people are searched by.
- **People**: up to `suggest_people` groups, drawn by the presenter's
  `suggestion`. Choosing one opens its record when the group has exactly one
  record that can be opened; otherwise it runs the full search.
- **Go to**: "Search all for …" (the typed text, sensitive values masked) and
  "Open search options".

"Search all" and "Open search options" post the text to `search_url` as a
full-page request (Turbo off), so the text never appears in a URL. Your search
action must render the full page for a non-frame POST.

Serve the list with `querylane_suggest` and `querylane_suggestions`
([Controller](controller.md#querylane_suggest)).

## Keyboard

| Where | Key | Does |
| --- | --- | --- |
| Anywhere outside a field | `/` | Focuses the search box (or the header box when the page has no search box) |
| Anywhere | ⌘K / Ctrl-K | Opens the palette |
| Search box | Enter | Searches now |
| Search box | Esc | Clears the box |
| Search box | ↓ | Moves to the first record |
| Record | ↑ ↓ | Previous or next record |
| Record | Enter | Opens the record (its Open button) |
| Record | Space | Opens or closes the preview |
| Preview open | Esc | Closes the preview |
| Options field | Enter | Applies the panel |
| Options panel | Esc | Cancels |
| Saved name field | Enter | Saves |
| Suggest box | ↑ ↓ | Moves through suggestions |
| Suggest box | Enter | Chooses the highlighted suggestion, or Search all |
| Suggest box | Tab | Completes the highlighted (or first) operator |
| Header box | Esc | Hides the list, then leaves the box |
| Palette | Esc | Closes the palette |

The focused record survives a frame refresh. Suggestions that are out of date
(the user typed since) ignore keys and clicks until the new list arrives.

## Turbo snapshot cache

Before Turbo caches a page, the box and the suggest box clear the input, the
results frame and the suggestion list. Back and forward never restore query text
or results.
