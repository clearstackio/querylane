# Query language

This page is for the people who type into the box and for the developers who
define what the box understands. The examples use the dummy app's definition:
names, `last4:`, `team:` and `is:` (alias `status:`).

## The short version

| Type | Finds |
| --- | --- |
| `smith` | Names containing "smith" |
| `smith john` | Names containing both words |
| `"van der berg"` | That exact phrase |
| `team:ops` | Records whose team is ops |
| `smith team:ops` | Both (terms are joined with AND) |
| `team:ops OR team:billing` | Either team |
| `-is:terminated` or `NOT is:terminated` | Everything except terminated records |
| `(team:ops OR team:billing) is:active` | Active records on either team |
| `smith 5432` | "smith" with the last four 5432 (the box worked out that 5432 is a last four) |

Press **Syntax help** under the box to see the operators of the page you are on.

## Words

Plain words search names (the definition's default text operator). Every word
must match. The backend matches the last word as a prefix, so `smi` finds
"Smith".

A `*` in a word is dropped: `smi*` is the same as `smi`. Prefix matching is
built in, and old habits keep working.

Quote words to search them as a phrase: `"ann lee"`. Inside quotes, write `\"`
for a quote and `\\` for a backslash.

## Operators

An operator is a key, a colon and a value, with no space after the colon:
`team:ops`. Keys are case-insensitive (`TEAM:ops` works). Quote a value that has
spaces: `team:"customer care"`.

There are three kinds:

- **Text operators** search free text in other attributes, for example
  `id:12345` (an ID that starts with 12345). A query uses one text operator at
  most: `smith id:12345` is an error.
- **Filters** match a value exactly: `team:ops`. Some normalize what you type
  first (an SSN filter may drop dashes) and check its shape (9 digits).
- **Flags** are named values: `is:active`. Values are case-insensitive. A family
  can have more than one key (`status:active` is the same as `is:active`).

A `*` inside an operator value is not a wildcard. Filters match exactly, so
`team:op*` looks for a team literally called "op*".

## Combining terms

- Terms side by side must all match (AND).
- `OR` (in capitals) between two terms matches either. `OR` binds tighter than
  the implicit AND: `team:ops OR team:billing is:active` means
  `(team:ops OR team:billing) AND is:active`.
- `-` directly before a term, or `NOT ` with a space, excludes it: `-is:terminated`,
  `NOT is:terminated`. It applies to the next term or parenthesized group only.
- Parentheses group terms: `-(team:ops OR team:billing)`.

`OR`, `NOT`, `-` and parentheses work on operators, not on names. `smith OR
jones`, `-smith` and `(smith is:active)` are errors. Search one name at a time.

Lower-case `or` and `not` are ordinary words.

## Limits

A query can have at most 256 characters, 20 terms and 3 levels of parentheses.
The host app can change these limits.

## Interpreted tokens

The host can teach the box to read bare tokens. In the dummy app, four digits
are a last four: `smith 5432` searches the name "smith" and `last4:5432`. The
chip says what the box understood ("Last four 5432").

When a token could mean something else, the chip offers it: **Policy 5432
instead**. Pressing it rewrites the box to `smith policy:5432`.

To stop a token from being interpreted, quote it: `"5432"` searches names.

## Short words

Some pages need at least a few letters before they search (the dummy app needs
3). While every word is shorter and there is no operator, the page says "Type at
least 3 letters of a name, or add an operator" and keeps the last results.

## Errors

A query that cannot run is not searched. The page says **Not searched** with the
reason, and the box underlines the characters at fault.

| You type | You see |
| --- | --- |
| `smith "unclosed` | Close the quote. |
| `team: ops` | team: needs a value. |
| `(team:ops` | Add the closing ). |
| `team:ops)` | Unexpected ). |
| `OR team:ops` | OR needs a term on both sides. |
| `()` | Empty parentheses. |
| `((((is:active))))` | Too many nested parentheses (3 at most). |
| `is:gone` | gone is not a value of is:. Try active, terminated. |
| `last4:12` | That value is not a valid last4: value. (sensitive values are never repeated) |
| `first:ann` | first: is not available yet. (a key reserved for later) |
| `smith OR jones` | OR joins operators, not names. Search one name at a time. |
| `smith id:12345` | Search name or id one at a time, or combine with … |

### Did you mean

A misspelled key close to a real one (two edits or fewer) gets a suggestion:

> Not searched. stauts: is not an operator. Did you mean status:? **Fix it**

**Fix it** rewrites the box to `smith status:active` and searches.

## How the page changes the box

The box is the whole search. Everything else on the page edits its text, and
the new text appears in the box:

| You press | The box becomes |
| --- | --- |
| Facet value "Active" on `smith` | `smith is:active` |
| A second value "Terminated" | `smith (is:active OR is:terminated)` |
| "Active" again | `smith is:terminated` |
| × on the "Team ops" chip of `smith team:ops` | `smith` |
| Clear | (empty) |
| "Search all team" (a widen button) when nothing matched | the query without its `team:` facet terms |
| "Drop Team ops" when nothing matched | the query without `team:ops` |
| "Allow fewer name matches" | same text; names match on fewer words |
| Search in the options panel | the text the panel's fields write |
| A saved search | that search's text |

A facet value counts as ticked only when the query has it at the top level,
either alone (`is:active`) or in an OR group made only of that operator
(`(is:active OR is:terminated)`). A value in another shape, such as
`-is:active` or `(is:active OR team:ops)`, stays as typed; ticking the facet
then adds `is:active` at the end.
