# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Searching Meilisearch through querylane", :meilisearch do
  let(:definition) { DummySearch.definition }
  let(:scope) { Querylane::Scope.new(staff: Querylane::Filter.everything, contractors: Querylane::Filter.eq(:team, "ops")) }

  def search(query, **params)
    request = Querylane::Request.new(definition: definition, query: query, **params)
    Querylane::Search.new(definition: definition, request: request, scope: scope).call
  end

  it "searches a name with an interpreted last four across indexes, inside the scope" do
    result = search("smith 5432", per: "10")

    expect(result.state).to eq(:ok)
    expect(result.hits.map(&:id)).to contain_exactly("s1", "s2", "s3", "c1")
    expect(result).to have_attributes(total: 4, total_kind: :exact)
    expect(result.chips.map(&:label)).to eq(["Name contains smith", "Last four 5432"])
  end

  it "never returns or counts records outside the scope, even with OR and NOT" do
    result = search("smith (team:secret OR team:ops) -is:terminated")

    expect(result.hits.map(&:id)).to eq(["c1"])
    secret = result.facets.find { |facet| facet.key == :team }.values.find { |value| value.value == "secret" }
    expect(secret).to have_attributes(ticked: true, count: 0)
  end

  it "counts facets disjunctively and shows ticked values" do
    status = search("smith is:active").facets.find { |facet| facet.key == :status }

    expect(status.values.map { |value| [value.value, value.count, value.ticked] }).to eq([["active", 3, true], ["terminated", 1, false]])
  end

  it "rewrites the query when a facet value is toggled" do
    result = search("smith", toggle: "team:billing", revision: 4, per: "10")

    expect(result).to have_attributes(query: "smith team:billing", rewritten: true, revision: 4)
    expect(result.hits.map(&:id)).to contain_exactly("s1", "s3")
  end

  it "removes a chip's term" do
    result = search("smith 5432", remove: "1")

    expect(result).to have_attributes(query: "smith", rewritten: true)
  end

  it "highlights matched words with private markers" do
    hit = search("smith").hits.find { |candidate| candidate.id == "s1" }

    expect(hit.formatted["full_name"]).to eq("\u0001SMITH\u0002, JOHN")
  end

  it "sorts across indexes and pages by records" do
    result = search("smith", sort: "name", per: "2", page: "2")

    expect(result.hits.map { |hit| hit.document["full_name"] }).to eq(["SMITHERS, JANE", "SMYTHE, ROBERT"])
    expect(result.pages).to eq(2)
  end

  it "reports invalid queries without searching" do
    result = search("smith stauts:active")

    expect(result.state).to eq(:invalid)
    expect(result.error.message).to include("Did you mean status:?")
  end

  it "fails closed when Meilisearch is unreachable" do
    searcher = Querylane::Searchers::Meilisearch.new(client: Meilisearch::Client.new("http://localhost:1", nil, timeout: 1, max_retries: 0))
    request = Querylane::Request.new(definition: definition, query: "smith")
    result = Querylane::Search.new(definition: definition, request: request, scope: scope, searcher: searcher).call

    expect(result.state).to eq(:unavailable)
    expect(result.hits).to be_empty
  end

  it "has a doctor that finds missing index settings" do
    problems = Querylane::Doctor.check(definition, client: DummySearch.client)

    expect(problems).to be_empty
  end
end

RSpec.describe "Rewrites offered on chips and empty results", :meilisearch do
  let(:definition) { DummySearch.definition }
  let(:scope) { Querylane::Scope.new(staff: Querylane::Filter.everything, contractors: Querylane::Filter.eq(:team, "ops")) }

  def search(query, **params)
    Querylane::Search.new(definition: definition, request: Querylane::Request.new(definition: definition, query: query, per: "10", **params), scope: scope).call
  end

  it "widens a facet when nothing matches" do
    empty = search("lee is:terminated")
    widened = search("lee is:terminated", widen: "status")

    expect(empty).to have_attributes(state: :empty)
    expect(empty.widenable_facets.map(&:key)).to eq([:status])
    expect(widened).to have_attributes(query: "lee", rewritten: true, state: :ok)
  end

  it "relaxes name matching on request" do
    expect(search("smith nobody").state).to eq(:empty)
    expect(search("smith nobody", relax: "1")).to have_attributes(state: :ok, relaxed: true)
  end
end
