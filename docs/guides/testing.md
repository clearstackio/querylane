# Testing

This page has two parts: testing an app that uses querylane, and running the
gem's own suite.

## Testing your app

### Unit-test the definition

Most of what a definition means can be checked without a backend:

```ruby
RSpec.describe "PEOPLE definition" do
  def analyze(text) = Querylane::Query.analyze(PeopleSearch.definition, text)

  it "reads four digits as a last four" do
    query = analyze("smith 5432")

    expect(Querylane::Chips.for(query).map(&:label)).to eq(["Name contains smith", "Last four 5432"])
  end

  it "suggests the operator people meant" do
    expect(analyze("stauts:active").error.message).to eq("stauts: is not an operator. Did you mean status:?")
  end

  it "ticks a status facet in the query text" do
    definition = PeopleSearch.definition
    query = analyze("smith")

    expect(Querylane::Rewriter.toggle(query, definition.facet(:status), "active")).to eq("smith is:active")
  end

  it "never saves a last four" do
    expect(Querylane::Saving.refusal(analyze("smith 5432"))).to be_present
  end
end
```

Building the definition is itself a test: a broken declaration raises
`Querylane::ConfigurationError`.

### Stub the searcher

A searcher is any object with `search(definition:, scope:, page:, counts:)`
returning a `Querylane::Searchers::Meilisearch::Response`
(`hits, total, counts, page_limit, backend_calls`). A fake one lets request
specs run without Meilisearch:

```ruby
class FakeSearcher
  attr_reader :scope

  def initialize(hits) = @hits = hits

  def search(definition:, scope:, page:, counts:)
    @scope = scope
    Querylane::Searchers::Meilisearch::Response.new(@hits, @hits.size, {total: @hits.size}, 10, 1)
  end
end

hit = Querylane::Result::Hit.new(index: :staff, id: "s1", document: {"id" => "s1", "full_name" => "SMITH, JOHN"},
  formatted: {}, ranking_details: {})
```

```ruby
around do |example|
  original = Querylane.configuration.searcher
  Querylane.configuration.searcher = FakeSearcher.new([hit])
  example.run
ensure
  Querylane.configuration.searcher = original
end
```

`counts` may omit facet keys (those facets then show "Counts unavailable"), or be
`nil` to simulate a failed count batch. Raise `Querylane::SearchUnavailable` to
test the unavailable state. Add `group_counts(definition:, scope:, attribute:,
values:)` returning `{value_downcased => count}` to test "more records".

`Querylane.reset_configuration!` resets every setting; call it after examples
that change configuration.

### Request specs

Post like the box does, with the `Turbo-Frame` header:

```ruby
it "answers the frame only, never cached" do
  post "/search", params: {search_query: "smith 5432"}, headers: {"Turbo-Frame" => "people-results"}

  expect(response.headers["Cache-Control"]).to eq("no-store")
  expect(response.body).to include('<turbo-frame id="people-results"').and include("Last four 5432")
  expect(response.body).not_to include("<html")
end

it "sends a rewritten query back to the box" do
  post "/search", params: {search_query: "smith", toggle: "status:active", revision: "7"},
    headers: {"Turbo-Frame" => "people-results"}

  expect(response.body).to include('<turbo-stream action="querylane_set_query" target="people-box" data-revision="7">')
end

it "refuses query text in a URL" do
  get "/", params: {search_query: "smith"}

  expect(response).to have_http_status(:bad_request)
end
```

Check the scope your controller builds by reading it back from a fake searcher
(`searcher.scope.filter_for(:staff)`), or render it with
`Querylane::Searchers::Meilisearch::Expression.render(filter)`.

Other frames: `people-writes` with `compose_preview=1` and `compose[...]`; a
group token from `data-querylane-group` posted as `group=` with the
`people-preview` or `people-related-…` frame; `find-list` for a suggest box.

### System specs

The box is a real `<input>` with a label, so Capybara's `fill_in` works:

```ruby
visit "/"
fill_in "Search Text", with: "smith 5432"
expect(page).to have_css(".ql-chip", text: "Last four 5432")

find(".ql-facet-value", text: "Active").click
expect(page).to have_field("Search Text", with: "smith 5432 is:active")
```

Wait for something the answer renders (a chip, a row) rather than sleeping:
typing searches after a debounce. Stable hooks: the input id (`input_id:`), the
info line (`info_id:`), the page-size select (`per_id:`), `.ql-chip`,
`.ql-facet-value[aria-checked]`, `.ql-group`, `[data-querylane-record]`.
Rendered text keeps its source case (the stylesheet uses no `text-transform`).

## Running the gem's suite

Setup is in [CONTRIBUTING](../../CONTRIBUTING.md#setup). Then:

```sh
MEILISEARCH_URL=http://localhost:7700 MEILISEARCH_API_KEY=your-key bundle exec rspec
bundle exec rspec spec/querylane          # unit specs only, no backend
bin/lint                                  # StandardRB and FracturedJSON
```

| Layer | Where | Needs |
| --- | --- | --- |
| Unit | `spec/querylane/` | Nothing |
| Integration | `spec/integration/` | Meilisearch |
| Request | `spec/requests/` | Meilisearch, the dummy app |
| System | `spec/system/` | Meilisearch, Playwright Chromium |

Examples tagged `:meilisearch` are skipped when Meilisearch is not reachable.
When it is, the suite drops and recreates the indexes `querylane_spec_staff` and
`querylane_spec_contractors` (fixtures in `spec/support/meilisearch_fixtures.rb`).
Point `MEILISEARCH_URL` at a server where that is fine.

System specs drive Chromium through `capybara-playwright-driver`, using
`node_modules/.bin/playwright`. Install it with `npm install` and
`npx playwright install chromium`.

## Waiting for an answer in browser specs

Turbo replaces a frame's contents but keeps the frame element's attributes,
so read the answer's state from inside the frame: the hidden
`[data-querylane-state]` element carries `data-revision` (the revision the
answer belongs to). A search has answered when that equals the form's
`revision` field and the frame has no `busy` attribute:

```ruby
answered = page.evaluate_script(<<~JS)
  (() => {
    const state = document.querySelector("turbo-frame#people-results [data-querylane-state]")
    const revision = document.querySelector("#people-form [name=revision]")
    return !!state && state.dataset.revision === revision.value &&
      !document.querySelector("turbo-frame#people-results").hasAttribute("busy")
  })()
JS
```
