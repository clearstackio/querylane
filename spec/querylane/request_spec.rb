# frozen_string_literal: true

RSpec.describe Querylane::Request do
  let(:definition) { TestSearch::DEFINITION }

  it "allowlists sort and per, bounds page and parses a facet toggle" do
    request = described_class.from_params({"search_query" => "smith", "sort" => "evil", "per" => "500", "page" => "-3", "toggle" => "status:active"}, definition: definition)

    expect(request).to have_attributes(query: "smith", per: 25, page: 1)
    expect(request.sort.key).to eq(:best)
    expect(request.toggle).to eq([definition.facet(:status), "active"])
  end

  it "resets the page when the query is rewritten" do
    expect(described_class.new(definition: definition, page: "3", remove: "0").page).to eq(1)
    expect(described_class.new(definition: definition, page: "3").page).to eq(3)
  end
end

RSpec.describe Querylane::Search, "clear" do
  it "clears the query without searching" do
    request = Querylane::Request.new(definition: TestSearch::DEFINITION, query: "smith is:active", clear: "1")
    result = described_class.new(definition: TestSearch::DEFINITION, request: request, scope: Querylane::Scope.unrestricted(:employees), searcher: Object.new).call

    expect(result).to have_attributes(state: :first_load, query: "", rewritten: true)
  end
end

RSpec.describe Querylane::Request, "as words" do
  it "reads a chip index and rewrites from the first page" do
    request = described_class.from_params({"as_words" => "2", "page" => "4"}, definition: TestSearch::DEFINITION)

    expect(request).to have_attributes(as_words: 2, page: 1)
    expect(described_class.new(definition: TestSearch::DEFINITION, as_words: "x").as_words).to be_nil
  end
end
