# Theming

querylane draws its widgets with Bootstrap 5 classes plus its own stylesheet,
`querylane.css`. You can change colors and sizes with CSS custom properties,
replace any partial, and change every piece of copy through translations.

## The stylesheet

```erb
<%= stylesheet_link_tag "querylane" %>
```

It is plain CSS, scoped to `.ql-*` and `.querylane-*` classes, and works with
Sprockets and Propshaft (the engine adds it to the Sprockets precompile list).
It deliberately avoids CSS that SassC-based compressors reject:

- no `min()`, `max()` or `clamp()`;
- no space-separated `rgb()` (`rgb(0 0 0 / 50%)`);
- no `text-transform` (small headings use `font-variant-caps: all-small-caps`,
  so the rendered text keeps its source case for tests that read it).

The `hidden` attribute always wins inside querylane widgets
(`[hidden] { display: none !important }`), even where a rule sets `display`.

## Custom properties

Set them on `:root` or on a wrapper element.

| Property | Default | Used for |
| --- | --- | --- |
| `--ql-accent` | `var(--bs-primary, #0d6efd)` | Box border, operator keys, focus marks |
| `--ql-accent-soft` | `#e5edff` | Focus glow around the box |
| `--ql-heading` | `#262b31` | Headings, caret |
| `--ql-text` | `#262b31` | Body text |
| `--ql-muted` | `#505050` | Secondary text |
| `--ql-faint` | `#767676` | Placeholders, hints |
| `--ql-border` | `#c1c1c1` | Field borders |
| `--ql-rule` | `#e3e5ea` | Dividers |
| `--ql-surface` | `#ffffff` | Box and panel backgrounds |
| `--ql-surface-alt` | `#f9faff` | Focused group background |
| `--ql-chip` | `#f3f4f9` | Chip background |
| `--ql-highlight` | `#fff0a8` | `<mark>` around matched words |
| `--ql-error` | `#b01c1c` | Invalid box border, error underline |
| `--ql-success-bg`, `--ql-success-fg` | `#e7f6ee`, `#1e7f4f` | `:success` badges |
| `--ql-warning-bg`, `--ql-warning-fg` | `#fff6d6`, `#7a5c00` | `:warning` badges |
| `--ql-danger-bg`, `--ql-danger-fg` | `#fdf5f5`, `#b01c1c` | `:danger` badges |
| `--ql-info-bg`, `--ql-info-fg` | `#e5edff`, `#002e64` | `:info` badges |
| `--ql-neutral-bg`, `--ql-neutral-fg` | `#f2f2f2`, `#505050` | `:neutral` badges |
| `--ql-font-mono` | `"IBM Plex Mono", "Roboto Mono", ui-monospace, …` | The box (it must be monospace, so masked dots keep their width) |
| `--ql-font-sans` | `inherit` | Placeholder and other text |
| `--ql-facets-width` | `212px` | Facet column |
| `--ql-outcome-width` | `220px` | Open/reason lane |
| `--ql-status-width` | `92px` | Status lane |

```css
.member-search {
  --ql-accent: #004ea8;
  --ql-highlight: #ffe9a6;
  --ql-facets-width: 240px;
}
```

The stylesheet has no dark-mode values; set the properties under your own
`prefers-color-scheme` rule if you need one. It honors `forced-colors` and
`prefers-reduced-motion`.

### State classes and attributes

| Selector | When |
| --- | --- |
| `.ql-box-busy` | The results frame is loading |
| `.ql-box-invalid` | The query has an error |
| `.ql-results[busy]` | Turbo is loading the frame |
| `[data-querylane-stale]` | The user typed since this frame or list was rendered |
| `.ql-box-saved[aria-pressed="true"]` | The box holds a saved search |
| `.ql-masked` | A masked options-panel field (`-webkit-text-security: disc`) |

## Bootstrap

The partials use Bootstrap 5 components only, never its grid or utility
classes: `btn`, `btn-primary`, `btn-outline-primary`, `btn-sm`,
`form-control`, `form-control-sm`, `form-select`, `form-select-sm`,
`pagination`, `pagination-sm`, `page-item` and `page-link`. Hidden labels use
querylane's own `.ql-visually-hidden`. `--ql-accent` follows `--bs-primary`
when it is set.

Controls follow one hierarchy, so a host page can keep its single solid
button for a commit:

| Level | Class | Controls |
| --- | --- | --- |
| Commit | `btn btn-primary` | Save in the saved-searches popover |
| Apply | `btn btn-outline-primary` | the box's Search, the options panel's Search |
| Go | `.ql-go` | Open and View on a record (a button that posts, drawn as a bold link) |
| Quiet | `.ql-link` | Clear, Fix it, Syntax help, Cancel, Reset, the empty state's widen, drop and relax actions |

To give Go and Quiet your own link styles, extend them in your stylesheet
(Sass: `.ql-go { @extend .your-go-link; }`).

The box resets borders and shadows that host styles put on inputs.

## Overriding partials

Copy a partial to the same path in your app and edit it. Rails finds yours
first. Each partial's first line declares its locals
(`<%# locals: (result:, id:) -%>`); keep that line, since Rails rejects a
render that passes other locals.

| Partial | Draws | Locals |
| --- | --- | --- |
| `querylane/_form` | Search form and box | `result, id, url, input_id, label, placeholder, mask, button_id, options, help, extra` |
| `querylane/_results` | The results frame | `result, id, info_id, per_id, first_load, rows` |
| `querylane/_chips` | Chips row | `result, id` |
| `querylane/_help` | Syntax help popover | `definition, id, popover_id` (optional) |
| `querylane/_facets` | Facet column | `result, id` |
| `querylane/_toolbar` | Count, sort, page size | `result, id, per_id` |
| `querylane/_pager` | Pager | `result, id` |
| `querylane/_rows` | Grouped rows | `presenter` |
| `querylane/_group` | One group | `presenter, group, columns` |
| `querylane/_record` | One record | `presenter, hit, columns` |
| `querylane/_outcome` | Open button or reason | `outcome` |
| `querylane/_first_load` | First-load state | `definition` |
| `querylane/_empty` | Empty state | `result, id` |
| `querylane/_unavailable` | Backend failed | `result, id` |
| `querylane/_denied` | Access not checked | `result, id` |
| `querylane/_options`, `_options_row` | Options panel | `result, id`; `row, values, held, definition, id` |
| `querylane/_writes` | Panel "Writes" frame | `preview, id` |
| `querylane/_saved` | Saved searches popover | `result, id` |
| `querylane/_related` | "More records" frame | `result, presenter, frame` |
| `querylane/_preview` | Preview frame | `result, presenter, id` |
| `querylane/_suggest_box`, `_suggestions` | Suggest box and its list | see the partials |

`_unavailable` and `_denied` are the usual ones to override, for example to link
to a roster page when search is down.

Keep the ids, `data-*` attributes, `form=` attributes and button names when you
copy a partial: the Stimulus controllers and the server rely on them.

## Translations

All copy comes from `config/locales/querylane.en.yml` under `querylane.*`.
Override any key in your app's locale files:

```yaml
# config/locales/querylane.en.yml (in your app)
en:
  querylane:
    suggest:
      label: "Search people"
      placeholder: "Search people"
      search_all_empty: "Open People Search"
    group:
      more:
        one: "1 more record"
        other: "%{count} more records"
```

The shipped wording comes from a member-search app ("Search members", "for this
person", "member IDs, SSNs or last fours"). Review these groups for your domain:

| Group | Covers |
| --- | --- |
| `querylane.box.*` | Box label, placeholder, clear, Search, Options |
| `querylane.options.*` | Options panel. A row's `hint:` and `placeholder:` are your own keys (or text), declared on `p.row` |
| `querylane.suggest.*` | Suggest box, palette, list headings |
| `querylane.saved.*` | Saved searches, refusal and notices |
| `querylane.reasons.more` | "+N more" reasons |
| `querylane.errors.*` | Every query error: syntax (`close_quote`, `unexpected`, `needs_value`, …), limits (`too_long`, `too_deep`, `too_many_terms`), operators (`parked`, `unknown_operator`, `did_you_mean`), values (`filter_value`, `filter_value_hidden`, `flag_value`) and placement (`text_in_or`, `text_in_not`, `text_in_group`, `one_text_operator`, `one_text_operator_alone`, whose lists are joined by `list_or`). A filter's `invalid:` sentence follows `filter_value` |
| `querylane.group.*` | "More records", preview |
| `querylane.chips.*` | Chips row, `count` mask |
| `querylane.toolbar.*` | Count, sort, pager |
| `querylane.footer.*` | "Showing …" and key legend |
| `querylane.facets.*` | Facet notes and "Find…" |
| `querylane.help.*` | Syntax help |
| `querylane.states.*` | First load, short, empty (`drop`, `relax`, `as_words`: "Search "%{value}" as part of a name"), invalid, unavailable, denied |

A widen button looks up `querylane.states.widen_<facet key>` first (for example
`widen_team: "Search all teams"`), then `querylane.states.widen`.

The English defaults of `querylane.errors.*` also live in
`Querylane::Query::MESSAGES`, so a host that drops the gem's locale file still
gets them. Interpolated values are what the user typed, except a sensitive
filter's value, which `filter_value_hidden` never receives. The facet column's
accessible name is `querylane.facets.label`.
