# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The search endpoint", :meilisearch, type: :request do
  it "answers a frame request with the results frame only, never cached" do
    post "/search", params: {search_query: "smith 5432"}, headers: {"Turbo-Frame" => "people-results"}

    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.body).to include('<turbo-frame id="people-results"').and include("Last four 5432")
    expect(response.body).not_to include("<html")
    expect(response.body).to include("<mark>SMITH</mark>")
  end

  it "sends the rewritten query back as a set-query stream inside the frame" do
    post "/search", params: {search_query: "smith", toggle: "status:active", revision: "7"}, headers: {"Turbo-Frame" => "people-results"}

    expect(response.body).to match(%r{<turbo-stream action="querylane_set_query" target="people-box" data-revision="7"><template>smith is:active</template></turbo-stream>})
  end

  it "refuses a query in a GET request" do
    get "/", params: {search_query: "smith"}

    expect(response).to have_http_status(:bad_request)
  end

  it "filters the query from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter("search_query" => "smith 5432")).to eq("search_query" => "[FILTERED]")
  end

  it "opens the options panel filled from the box" do
    post "/search", params: {search_query: "smith 5432 (team:ops OR is:active)", options: "1"}, headers: {"Turbo-Frame" => "people-results"}

    expect(response.body).to include('id="people-options"').and include('name="compose[name]"').and include('value="smith"')
    expect(response.body).to include("Kept as typed: (team:ops OR is:active).")
    expect(response.body).to match(/<div class="ql-under" inert>/)
  end

  it "draws a row's placeholder and hint, the hint describing the row's field" do
    post "/search", params: {search_query: "smith", options: "1"}, headers: {"Turbo-Frame" => "people-results"}
    page = Nokogiri::HTML(response.body)
    team = page.at_css('input[name="compose[team]"]')

    expect(page.at_css('input[name="compose[name]"]')["placeholder"]).to eq("Part of any name")
    expect(page.at_css("##{team["aria-describedby"]}").text).to eq("One exact team name, any case.")
    expect(team["placeholder"]).to be_nil
  end

  it "previews what the fields would write, without searching" do
    searcher = Querylane.configuration.searcher
    Querylane.configuration.searcher = -> { raise "no search for a preview" }
    post "/search", params: {search_query: "smith", compose_preview: "1", compose: {name: "agrawal", last4: "5432", is: ["active"]}},
      headers: {"Turbo-Frame" => "people-writes"}

    expect(response.body).to include('<turbo-frame id="people-writes"').and include("agrawal last4:5432 is:active")
    expect(response.body).not_to include("people-results")
  ensure
    Querylane.configuration.searcher = searcher
  end

  it "writes the composed query back to the box when the panel searches" do
    post "/search", params: {search_query: "smith", compose_submit: "1", revision: "3", compose: {name: "jones", team: "ops"}},
      headers: {"Turbo-Frame" => "people-results"}

    expect(response.body).to include("<template>jones team:ops</template>")
    expect(response.body).not_to include('id="people-options"')
  end

  describe "a group's records" do
    def group_token(query)
      post "/search", params: {search_query: query}, headers: {"Turbo-Frame" => "people-results"}
      response.body[/data-querylane-group="([^"]+)"/, 1].then { |token| CGI.unescapeHTML(token) }
    end

    it "loads the records the page did not show, any status, without the group key in the page" do
      token = group_token("smith is:active")
      frame = response.body[/id="(people-related-\h{16})"/, 1]
      # Encrypted tokens are random base64 and may spell "p1" by chance.
      expect(response.body.gsub(%r{[\w+/=]+--[\w+/=]+--[\w+/=]+}, "")).not_to include("p1")

      post "/search", params: {group: token}, headers: {"Turbo-Frame" => frame}

      expect(response.body).to include(%(<turbo-frame id="#{frame}")).and include("All records for this person, any status · 2 of 2")
      expect(response.body).to include("claims").and include("Terminated")
      expect(response.body.scan("data-querylane-record=").size).to eq(1)
    end

    it "offers more records only to groups that have records off the page, with how many" do
      post "/search", params: {search_query: "smith is:active"}, headers: {"Turbo-Frame" => "people-results"}
      groups = Nokogiri::HTML(response.body).css(".ql-group")
      john = groups.find { |group| group.text.include?("JOHN") }
      jane = groups.find { |group| group.text.include?("JANE") }

      expect(john.at_css(".ql-more-open").text).to eq("1 more record for this person")
      expect(jane.at_css(".ql-more")).to be_nil
      expect(jane["data-querylane-group"]).to be_present
    end

    it "previews every record of the group" do
      token = group_token("smith is:active")

      post "/search", params: {group: token}, headers: {"Turbo-Frame" => "people-preview"}

      expect(response.body).to include('<turbo-frame id="people-preview"').and include("2 records you can see, any status")
      expect(response.body).to include("billing").and include("claims")
    end

    it "keeps the scope: a group never reaches records the user cannot see" do
      token = Querylane::GroupToken.write(DummySearch.definition, "p5", [])

      post "/search", params: {group: token}, headers: {"Turbo-Frame" => "people-preview"}

      expect(response.body).not_to include("HIDDEN")
    end

    it "refuses a forged token" do
      post "/search", params: {group: "forged"}, headers: {"Turbo-Frame" => "people-preview"}

      expect(response.body).to include("These records could not be loaded")
    end
  end

  describe "suggestions" do
    it "completes operators, lists people by the rest of the text and never repeats the query in attributes" do
      post "/suggest", params: {search_query: "smith te"}, headers: {"Turbo-Frame" => "find-list"}

      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include('<turbo-frame id="find-list"').and include('data-querylane-complete="team:"')
      expect(response.body).to include("<mark>SMITH</mark>, JOHN").and include("ROBERT")
      expect(response.body).to include("Search all for smith te")
      expect(response.body).not_to match(/="[^"]*smith te/)
    end

    it "answers the frame that asked (the palette)" do
      post "/suggest", params: {search_query: "lee 1180"}, headers: {"Turbo-Frame" => "palette-list"}

      expect(response.body).to include('<turbo-frame id="palette-list"').and include("<mark>LEE</mark>, ANN")
      expect(response.body).to include("Search all for lee 1180")
    end
  end

  describe "saved searches" do
    before { MemorySavedSearches.reset! }

    it "saves a search without sensitive values and runs it again by id" do
      post "/search", params: {search_query: "smith team:ops", save_search: "1", saved_name: "Ops Smiths"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("Search saved.").and include("Ops Smiths")
      id = MemorySavedSearches.items.first.id

      post "/search", params: {search_query: "", saved: id, revision: "4"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("<template>smith team:ops</template>")
    end

    it "refuses a search holding a value the box read as a last four, and offers the rest" do
      post "/search", params: {search_query: "smith 5432", save_search: "1"}, headers: {"Turbo-Frame" => "people-results"}

      expect(MemorySavedSearches.items).to be_empty
      expect(response.body).to include("This search was not saved")
      expect(response.body).to include("“5432” is read as last four").and include("save “smith” alone")
    end
  end

  describe "review fixes" do
    it "refuses query text by GET on every endpoint and filters panel fields from logs" do
      Rails.application.routes.draw do
        root "searches#show"
        post "search", to: "searches#search", as: :search
        match "suggest", to: "searches#suggest", as: :suggest, via: %i[get post]
        post "open", to: "searches#open", as: :open_record
        get "elsewhere", to: "searches#elsewhere"
      end
      get "/suggest", params: {search_query: "smith"}

      expect(response).to have_http_status(:bad_request)
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      expect(filter.filter("compose" => {"ssn" => "123456789"})).to eq("compose" => "[FILTERED]")
    ensure
      Rails.application.reload_routes!
    end

    it "runs a saved search even when the box holds an unfinished query" do
      MemorySavedSearches.reset!
      MemorySavedSearches.create(context: nil, name: "Ops", query: "team:ops")

      post "/search", params: {search_query: %(smith "unfinished), saved: "1", revision: "2"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("<template>team:ops</template>")
    end
  end

  describe "states and corrections" do
    it "fixes a misspelled operator in one click" do
      post "/search", params: {search_query: "smith stauts:active", revision: "5"}, headers: {"Turbo-Frame" => "people-results"}
      expect(response.body).to include("Did you mean status:?").and include('name="fix"')

      post "/search", params: {search_query: "smith stauts:active", fix: "1", revision: "5"}, headers: {"Turbo-Frame" => "people-results"}
      expect(response.body).to include("<template>smith status:active</template>")
    end

    it "offers an exact filter that found nothing as name words, and rewrites the box to them" do
      post "/search", params: {search_query: "team:lee"}, headers: {"Turbo-Frame" => "people-results"}
      link = Nokogiri::HTML(response.body).at_css('.ql-empty button[name="as_words"]')

      expect(link.text).to eq(%(Search "lee" as part of a name))
      expect(link["class"]).to eq("ql-link")

      post "/search", params: {search_query: "team:lee", as_words: link["value"], revision: "6"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("<template>lee</template>").and include("<mark>LEE</mark>, ANN")
    end

    it "adds the filter's own sentence to a bad value" do
      post "/search", params: {search_query: "team:42"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("&quot;42&quot; is not a valid team: value. Team names have no digits.")
    end

    it "says a parked operator is not available yet" do
      post "/search", params: {search_query: "first:ann"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("first: is not available yet.")
    end

    it "does not search words that are too short" do
      searcher = Querylane.configuration.searcher
      Querylane.configuration.searcher = -> { raise "no search for a short query" }
      post "/search", params: {search_query: "sm"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("Type at least 3 letters")
    ensure
      Querylane.configuration.searcher = searcher
    end

    it "shows a denied scope as its own state without searching" do
      result = Querylane::Search.new(definition: DummySearch.definition, request: Querylane::Request.new(definition: DummySearch.definition, query: "smith"),
        scope: Querylane::Scope.denied, searcher: Object.new).call

      expect(result.state).to eq(:denied)
    end

    it "lists further reasons behind +N more" do
      post "/search", params: {search_query: "smith 5432"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include("+1 more").and include("Combo-billed division.")
    end
  end

  describe "control levels" do
    it "puts the box in a search landmark whose Search applies, never commits" do
      get "/"

      expect(response.body).to match(%r{<search class="ql-search">\s*<form[^>]*id="people-form"})
      expect(response.body).to match(/<button type="submit" class="btn btn-outline-primary ql-box-submit"/)
    end

    it "draws Open as a Go link that still posts, and no utility classes" do
      post "/search", params: {search_query: "smith"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to match(%r{<form class="ql-open-form"[^>]*method="post"[^>]*>.*?<button class="ql-go ql-open"}m)
      expect(response.body).not_to match(/class="[^"]*\b(visually-hidden|mb-0|d-inline)\b/)
    end

    it "names the facet column from the locale and each help popover by where it shows" do
      post "/search", params: {search_query: "smith", options: "1"}, headers: {"Turbo-Frame" => "people-results"}

      expect(response.body).to include(%(<aside class="ql-facets" aria-label="#{I18n.t("querylane.facets.label")}">))
      expect(response.body).to include('popovertarget="people-help"').and include('popovertarget="people-options-help"')
    end

    it "puts the header box and the palette's form in search landmarks, the palette's inside its dialog" do
      get "/elsewhere"

      expect(response.body).to match(%r{<search class="ql-search">\s*<form[^>]*id="find-form"})
      expect(response.body).to match(%r{<dialog class="ql-palette".*?<search class="ql-search">\s*<form[^>]*id="palette-form".*?</search>.*?</dialog>}m)
      expect(response.body).not_to include('role="search"')
    end
  end
end
