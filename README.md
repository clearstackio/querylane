# querylane

querylane is a Rails engine that adds a Gmail-style search box to a Rails app.
People type plain words and operators (`smith team:ops -is:terminated`). The
server parses the text, searches one or more Meilisearch indexes inside a
permission scope, and renders the results with the engine's partials and
Stimulus controllers. The query text is the only search state: facets, chips
and the options panel all rewrite the text in the box, so what you see in the
box is always what was searched.

[![Build Status](https://github.com/clearstackio/querylane/actions/workflows/ci.yml/badge.svg)](https://github.com/clearstackio/querylane/actions)

## Features

- A small query language: words, `key:value` operators, quotes, `OR`, `-`/`NOT`,
  parentheses. Errors point at the exact characters, suggest a fix ("Did you mean
  `status:`?") and offer **Fix it**.
- An interpreter hook that reads bare tokens as operators (`5432` as a last four),
  with "… instead" buttons for other readings.
- "Searching for" chips with × to remove a term. Sensitive values are masked.
- Facets with counts (OR within a facet, AND across facets) that tick and untick
  terms in the query text. A "Find…" box for long facet lists.
- Toolbar with count, sort, page size and pager.
- Result rows grouped by an attribute (for example one person), drawn from your
  `Querylane::Presenter`. "N more records" for a group and a Space-key preview.
- An options panel that turns the query into fields and back.
- A header search box with suggestions and a ⌘K / Ctrl-K palette.
- Saved searches through a store you provide.
- Clear states: first load, too short, empty (with widen, drop and relax buttons),
  invalid, unavailable and access denied.
- Keyboard support: `/`, ↑ ↓, Enter, Space, Esc, Tab, ⌘K.
- Privacy defaults: queries travel by POST only, responses are `no-store`, query
  parameters are filtered from logs, group handles are encrypted, and saved
  searches refuse sensitive values.

## Requirements

| | Version |
| --- | --- |
| Ruby | 3.3 or newer |
| Rails | 8.1 (`~> 8.1.0`) |
| Meilisearch server | 1.13 or newer |
| `meilisearch` gem | `~> 0.33.0` (you add it to your Gemfile) |
| JavaScript peers | `@hotwired/turbo` 8, `@hotwired/stimulus` 3.2, `@github/combobox-nav` 3 |
| CSS | Bootstrap 5 (the partials use its button, form and pagination classes) |
| Browsers | Current browsers with the Popover API and `<dialog>` |

Turbo Drive may be on or off. The widgets only use Turbo Frames and one custom
Turbo Stream action.

## Installation

Add the gem and the Meilisearch client to your Gemfile:

```ruby
gem "querylane"
gem "meilisearch", "~> 0.33.0"
```

To try unreleased work, point the gem at the repository
(`gem "querylane", github: "clearstackio/querylane", branch: "master"`) and use a
local checkout without reinstalling:
`bundle config local.querylane /path/to/querylane`.

### JavaScript

Install the peer packages in your app:

```sh
npm install @hotwired/turbo @hotwired/stimulus @github/combobox-nav
```

The gem ships ES modules in `app/javascript/querylane/`. Your bundler must find
them, and must resolve the peers to your app's own copies (two copies of Turbo
would mean the custom stream action is registered on the wrong one).

**jsbundling with webpack.** Ask Bundler where the gem lives, so local overrides
and lockfile revisions use the same files:

```js
// webpack.config.js
const { execFileSync } = require("child_process")
const path = require("path")

const querylaneRoot = execFileSync("bundle", ["exec", "ruby", "-e", "print Gem.loaded_specs['querylane'].full_gem_path"],
  { cwd: __dirname, encoding: "utf8" }).trim()

module.exports = {
  // ...your config
  resolve: {
    alias: {
      querylane: path.join(querylaneRoot, "app/javascript/querylane"),
      "@hotwired/stimulus": path.resolve(__dirname, "node_modules/@hotwired/stimulus"),
      "@hotwired/turbo": path.resolve(__dirname, "node_modules/@hotwired/turbo"),
      "@github/combobox-nav": path.resolve(__dirname, "node_modules/@github/combobox-nav")
    }
  }
}
```

Webpack's watcher picks up edits to the gem. Restart it when the gem path changes.

**importmap-rails (Propshaft or Sprockets).** Nothing to configure for the
gem's own modules: when your app has a `config/importmap.rb`, the engine adds
`app/javascript` to the asset load path and draws the gem's
[`config/importmap.rb`](config/importmap.rb) into your app's map. That map pins
`querylane` and each module by its file name (`querylane/overlay.js`,
`querylane/controllers/box_controller.js`, ...), none of them preloaded, so
pages without a search box fetch nothing. Your app pins the peers, so the page
shares one copy of each with your own code:

```ruby
# config/importmap.rb
pin "@hotwired/stimulus", to: "stimulus.min.js"   # stimulus-rails
pin "@github/combobox-nav"                        # bin/importmap pin @github/combobox-nav
```

Turbo stays as your app loads it (turbo-rails' `turbo.min.js` pin is fine).
querylane never imports Turbo: it handles its one custom stream action through
the `turbo:before-stream-render` event, which every Turbo 8 copy dispatches.

On Sprockets, the modules are precompiled as they are. If your app sets
`config.assets.js_compressor`, it must parse ES module syntax (`import` and
`export`), or `assets:precompile` fails on querylane's files. Propshaft does not
compress.

**How the modules import each other.** As `querylane/overlay.js` and so on,
never by relative path: a relative import would miss the digested URLs
importmap-rails serves. The same names resolve under the webpack alias above,
an esbuild alias, the npm package in `app/javascript/querylane`, and a
hand-written import map with one `"querylane/"` prefix entry.

**Import maps without importmap-rails.** Serve the gem's `app/javascript`
directory and the peer packages as ES modules, then map `querylane` and the
`querylane/` prefix. The dummy app in [`spec/dummy`](spec/dummy/config/application.rb) does exactly
this with `Rack::Static` and an inline import map; see
[Getting started](docs/guides/getting-started.md#javascript).

Then register the controllers with your Stimulus application:

```js
import { registerControllers } from "querylane"

registerControllers(application)
```

`registerControllers` registers `querylane--box`, `querylane--results`,
`querylane--options` and `querylane--suggest`. Importing `querylane` also adds
the `querylane_set_query` Turbo Stream action. The gem never starts Stimulus and
never changes Turbo settings.

### Stylesheet

```erb
<%= stylesheet_link_tag "querylane" %>
```

It is plain CSS and works with Sprockets and Propshaft. Theme it with the
`--ql-*` custom properties ([Theming](docs/guides/theming.md)).

## Quick start

A complete, working version of this example lives in [`spec/dummy`](spec/dummy).

**1. Point querylane at Meilisearch.**

```ruby
# config/initializers/querylane.rb
Rails.application.config.to_prepare do
  Querylane.configure do |config|
    config.searcher = -> { Querylane::Searchers::Meilisearch.new(client: Meilisearch::Client.new(ENV["MEILISEARCH_URL"], ENV["MEILISEARCH_API_KEY"])) }
    # Why a search could not run (default: standard output).
    config.logger = Rails.logger
  end
end
```

**2. Describe the search.**

```ruby
# app/searches/people_search.rb
module PeopleSearch
  def self.definition
    @definition ||= Querylane::Definition.build(:people) do |d|
      d.index  :staff, name: "staff"
      d.text   :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
      d.filter :team, attribute: :team, label: "Team %{value}"
      d.flags  :is, alias: :status, attribute: :status_label, label: "Status",
                    values: {active: "Active", terminated: "Terminated"}
      d.facet  :status, flag: :is
      d.group  :person
    end
  end
end
```

**3. Search in a controller.**

```ruby
# config/routes.rb
get  "people", to: "people#index"
post "people/search", to: "people#search", as: :people_search
post "people/open", to: "people#open", as: :open_person # the row's Open button posts here

# app/controllers/people_controller.rb
class PeopleController < ApplicationController
  include Querylane::Controller

  def index
    @result = querylane_search(PeopleSearch.definition, scope: scope)
  end

  def search
    @result = querylane_search(PeopleSearch.definition, scope: scope)
    if querylane_frame?(:people)
      render partial: "people/results", locals: {result: @result}
    else
      render :index
    end
  end

  private

  # What this user may see. Built on the server, never from params.
  def scope = Querylane::Scope.new(staff: Querylane::Filter.eq(:company_id, current_user.company_id))
end
```

**4. Draw it.**

```erb
<%# app/views/people/index.html.erb %>
<%= querylane_form @result, id: :people, url: people_search_path %>
<%= render "people/results", result: @result %>

<%# app/views/people/_results.html.erb %>
<%= querylane_results result, id: :people, presenter: PersonPresenter %>
```

**5. Say how a record looks.**

```ruby
# app/presenters/person_presenter.rb
class PersonPresenter < Querylane::Presenter
  def columns = [Column.new(:team, "Team", 120)]

  def cells(hit) = [Cell.new(hit.document["team"], :strong)]

  def status(hit)
    (hit.document["status_label"] == "active") ? Badge.new("Active", :success) : Badge.new("Terminated", :neutral)
  end

  # Open is a full-page POST to the URL, with these params.
  def outcome(hit) = Action.new("Open", view.open_person_path, {id: hit.id}, :primary)
end
```

**6. Check the index settings.**

```sh
bin/rails "querylane:doctor[PeopleSearch.definition]"
```

The doctor lists every attribute the definition needs that the index does not
declare (searchable, filterable, sortable, typo tolerance, facet order).

## Learn more

| Guide | What it covers |
| --- | --- |
| [Getting started](docs/guides/getting-started.md) | An end-to-end first page: routes, frames, index settings, JavaScript, the doctor |
| [Definition](docs/guides/definition.md) | Every DSL method: operators, facets, sorts, interpreter, groups, panel, hooks |
| [Query language](docs/guides/query-language.md) | What people can type, precedence, errors, wildcards, interpreted tokens |
| [Widgets](docs/guides/widgets.md) | Each widget, its helper, params, frames and keys |
| [Presenter](docs/guides/presenter.md) | How result rows, groups and suggestions are drawn |
| [Controller](docs/guides/controller.md) | `querylane_search`, `_preview`, `_related`, `_suggest`, frames, guards |
| [Scope and hooks](docs/guides/scope-and-hooks.md) | Permission scopes, the Filter API, query-filter and results hooks |
| [Saved searches](docs/guides/saved-searches.md) | The store contract and what is refused |
| [Theming](docs/guides/theming.md) | CSS custom properties, partial overrides, translations |
| [Security](docs/guides/security.md) | The privacy model and what the host must do |
| [Testing](docs/guides/testing.md) | Testing a host app, and running the gem's suite |
| [Architecture](docs/architecture.md) | How a request flows through the gem (for contributors) |

Also: [CHANGELOG](CHANGELOG.md), [CONTRIBUTING](CONTRIBUTING.md),
[SECURITY](SECURITY.md), [all docs](docs/README.md).

## License

MIT. See [LICENSE](LICENSE).
