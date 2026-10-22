# Getting started

This guide builds one search page from scratch. Every piece matches the dummy
app in [`spec/dummy`](../../spec/dummy), which the gem's own browser specs run
against. When in doubt, read that app.

The example searches people in two Meilisearch indexes, `staff` and
`contractors`. Each document has an `id`, a `person` (the same person can have
several records), `full_name`, `id_last4`, `team`, `status_label` and `started`.

## 1. Install

Follow [Installation](../../README.md#installation) in the README: the gem, the
`meilisearch` gem, the three JavaScript peers and the stylesheet.

## 2. Configure the searcher

```ruby
# config/initializers/querylane.rb
Rails.application.config.to_prepare do
  Querylane.configure do |config|
    config.searcher = -> { Querylane::Searchers::Meilisearch.new(client: Meilisearch::Client.new(ENV.fetch("MEILISEARCH_URL"), ENV["MEILISEARCH_API_KEY"])) }
    # Why a search could not run (default: standard output).
    config.logger = Rails.logger
  end
end
```

`config.searcher` takes an object or a callable. A callable is called on every
search, so it follows code reloading and can build a client per request.
`to_prepare` re-runs the block after each reload in development.

Other settings and their defaults:

| Setting | Default | Meaning |
| --- | --- | --- |
| `param_name` | `:search_query` | Name of the query text parameter |
| `max_length` | `256` | Longest query, in characters |
| `max_depth` | `3` | Deepest nesting of parentheses |
| `max_terms` | `20` | Most terms in one query |
| `debounce_ms` | `300` | Pause after typing before the box searches |
| `allow_get_query` | `false` | Allow query text in a GET URL (leave off) |
| `group_token_ttl` | `3600` | Seconds a "more records" handle stays valid |
| `suggest_records` | `20` | Records read for suggestions |
| `suggest_people` | `5` | Groups shown in suggestions |

If you rename `param_name`, add the new name to
`config.filter_parameters` yourself (see [Security](security.md#logs)).

`Querylane::Searchers::Meilisearch.new` also takes `max_total_hits:` (default
`1000`). Pass it when you raise `pagination.maxTotalHits` on your indexes; the
pager and the "1,000+ records" count use it.

## 3. Write the definition

```ruby
# app/searches/dummy_search.rb (abridged from the dummy app)
module DummySearch
  module_function

  def definition
    @definition ||= Querylane::Definition.build(:people) do |d|
      d.index :staff, name: "querylane_spec_staff"
      d.index :contractors, name: "querylane_spec_contractors"
      d.text :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
      d.filter :last4, attribute: :id_last4, sensitive: true, format: /\A\d{4}\z/, label: "Last four %{value}", mask: :none
      d.filter :team, attribute: :team, label: "Team %{value}"
      d.flags :is, alias: :status, attribute: :status_label, label: "Status", values: {active: "Active", terminated: "Terminated"}
      d.facet :status, flag: :is
      d.facet :team, filter: :team, top: 5, show: 1, search: true
      d.sort :best, label: "Best match", default: true
      d.sort :name, label: "Name A–Z", by: {full_name: :asc}
      d.per 2, 10
      d.interpreter ->(token) { [:last4, token] if token.match?(/\A\d{4}\z/) }
      d.group :person
      d.min_text_length 3
    end
  end
end
```

`Definition.build` validates the declarations and freezes the result. A mistake
(a facet that points at nothing, a duplicate operator) raises
`Querylane::ConfigurationError` the first time the definition is built. The
[Definition guide](definition.md) covers every method.

## 4. Set up the indexes

querylane never changes index settings; your app owns them. The dummy app's
fixtures use these settings:

```ruby
index.update_settings(
  searchable_attributes: %w[full_name id_last4],
  filterable_attributes: %w[id_last4 team status_label person],
  sortable_attributes: %w[full_name],
  typo_tolerance: {"disableOnAttributes" => %w[id_last4]},
  faceting: {"sortFacetValuesBy" => {"*" => "count"}}
)
```

What each setting is for:

- **searchableAttributes**: every `d.text` attribute.
- **filterableAttributes**: every `d.filter` and attribute-based `d.flags`
  attribute, plus the `d.group` attribute ("more records" filters and counts by it).
- **sortableAttributes**: every attribute named in a `d.sort ... by:` or a
  `d.group ... order:`.
- **typoTolerance.disableOnAttributes**: the attributes of sensitive text
  operators, so an ID prefix never matches a "close" ID.
- **faceting.sortFacetValuesBy**: `"count"` for filter facets, so the top values
  are the most common ones.

Then ask the doctor:

```sh
bin/rails "querylane:doctor[DummySearch.definition]"
```

The argument is either a constant (`querylane:doctor[PEOPLE]`) or a
`Constant.method` call (`querylane:doctor[DummySearch.definition]`). Quote it in
zsh. The task prints one line per problem, for example
`querylane_spec_staff: team is not filterable`, and exits with status 1 if there
are any. With none it prints `querylane: people indexes are ready`.

The doctor reads the client from the configured Meilisearch searcher. It does
not check the `d.group` attribute, its `order:` attributes or the `d.retrieve`
list.

## 5. Routes

```ruby
# config/routes.rb
root "searches#show"
post "search", to: "searches#search", as: :search
post "open", to: "searches#open", as: :open_record      # a row's Open button
post "suggest", to: "searches#suggest", as: :suggest    # only for the suggest box
```

The search endpoint must accept POST. Every widget posts to it: typing, facets,
paging, the options panel, "more records" and the preview. The GET page renders
the empty search.

## 6. The controller

```ruby
class SearchesController < ApplicationController
  include Querylane::Controller

  def show
    @result = querylane_search(DummySearch.definition, scope: scope)
  end

  def search
    # The options panel's "Writes" line: no search.
    if querylane_frame?(:people, :writes)
      return render partial: "querylane/writes", locals: {preview: querylane_preview(DummySearch.definition), id: "people"}
    end

    # "More records" and the preview: all records of one group.
    if (related = querylane_related(DummySearch.definition, scope: scope))
      return render html: helpers.querylane_related(related, id: :people, presenter: PersonPresenter, frame: request.headers["Turbo-Frame"])
    end

    @result = querylane_search(DummySearch.definition, scope: scope)
    if querylane_frame?(:people)
      render partial: "searches/results", locals: {result: @result}
    else
      render :show # a full-page POST, e.g. "Search all" from the palette
    end
  end

  private

  # Contractors are visible only on the "ops" team.
  def scope
    Querylane::Scope.new(staff: Querylane::Filter.everything, contractors: Querylane::Filter.eq(:team, "ops"))
  end
end
```

Order matters: answer the `writes` frame first, then a group request, then the
search. The [Controller guide](controller.md) explains each call.

## 7. The views

```erb
<%# app/views/searches/show.html.erb %>
<h1>People</h1>
<%= querylane_form @result, id: :people, url: search_path, input_id: "people_query", label: "Search Text", mask: '\b\d{9}\b' %>
<%= render "searches/results", result: @result %>
```

```erb
<%# app/views/searches/_results.html.erb %>
<%= querylane_results result, id: :people, presenter: PersonPresenter, info_id: "people_info", per_id: "people_per" %>
```

The form sits outside the results frame, so typing never loses the caret. The
partial renders the `people-results` frame, which is also the whole response to
a frame request. The widget id (`:people`) ties the two together; use the same
id in `querylane_frame?`.

## 8. The presenter

```ruby
# app/presenters/person_presenter.rb
class PersonPresenter < Querylane::Presenter
  def columns = [Column.new(:team, "Team", 120), Column.new(:started, "Started", 100)]

  def subtitle(group) = "•••-#{group.hits.first.document["id_last4"]}"

  def cells(hit) = [Cell.new(hit.document["team"], :strong), Cell.new(hit.document["started"], :muted)]

  def status(hit)
    (hit.document["status_label"] == "active") ? Badge.new("Active", :success) : Badge.new("Terminated", :neutral)
  end

  def outcome(hit)
    if hit.document["status_label"] == "terminated"
      return Reason.new(text: "Terminated. Rehire them first.", link_label: "Rehire", link_url: "/rehire")
    end

    Action.new("Open ▸", view.open_record_path, {id: hit.id, index: hit.index}, :primary)
  end
end
```

The [Presenter guide](presenter.md) lists every method you can override.

## JavaScript

With webpack or importmap-rails, follow the README: importmap-rails picks up the
gem's pins on its own, and you pin only the peers. Without either, the dummy app
serves the gem's modules straight from disk and maps them in an import map. The
modules import each other as `querylane/overlay.js` and so on, so one
`"querylane/"` prefix entry covers them all:

```ruby
# config/application.rb (adapted from the dummy app)
gem_root = Querylane::Engine.root.to_s
config.middleware.insert_before ActionDispatch::Static, Rack::Static, urls: ["/querylane"],
  root: File.join(gem_root, "app/javascript"), header_rules: [[:all, {"Content-Type" => "text/javascript"}]], cascade: true
```

```erb
<%# app/views/layouts/application.html.erb %>
<%= stylesheet_link_tag "querylane" %>
<script type="importmap">
  {"imports": {
    "@github/combobox-nav": "/node_modules/@github/combobox-nav/dist/index.js",
    "@hotwired/stimulus": "/node_modules/@hotwired/stimulus/dist/stimulus.js",
    "@hotwired/turbo": "/node_modules/@hotwired/turbo/dist/turbo.es2017-esm.js",
    "querylane": "/querylane/index.js",
    "querylane/": "/querylane/"
  }}
</script>
<script type="module">
  import * as Turbo from "@hotwired/turbo"
  import { Application } from "@hotwired/stimulus"
  import { registerControllers } from "querylane"
  Turbo.session.drive = false
  registerControllers(Application.start())
</script>
```

The dummy app serves `/node_modules` the same way. In a real app, serve the
peer packages however your app already serves JavaScript; the only requirement
is that `querylane` and your page import the same Turbo and Stimulus modules.
The dummy app turns Turbo Drive off; querylane works either way.

## 9. Try it

Start the app, open the page and type `smith 5432`. You should see a "Last four
5432" chip, grouped rows, facet counts and "Showing 1 to 2 of 4 entries". Tick a
facet value: the box text changes to `smith 5432 is:active`.

## Next steps

- Add a [header box or palette](widgets.md#suggest-box-header-and-palette).
- Restrict what each user sees with a [Scope and hooks](scope-and-hooks.md).
- Let people [save searches](saved-searches.md).
- Match your design with [Theming](theming.md).
