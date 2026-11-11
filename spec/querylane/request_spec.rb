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

  it "reads a bounded deletion id without rewriting the query or resetting its page" do
    request = described_class.from_params({"delete_saved" => "12", "search_query" => "smith", "page" => "3"}, definition: definition)

    expect(request).to have_attributes(delete_saved: "12", query: "smith", page: 3, rewriting?: false)
    expect(described_class.from_params({"delete_saved" => "x" * 100}, definition: definition).delete_saved.length).to eq(64)
  end

  it "preserves the displayed page for deletion without overriding normal paging" do
    deleting = described_class.from_params({delete_saved: "12", delete_saved_page: "3"}, definition: definition)
    paging = described_class.from_params({delete_saved_page: "3", page: "2"}, definition: definition)

    expect(deleting.page).to eq(3)
    expect(paging.page).to eq(2)
  end

  it "normalizes false-valued deletion params the same way for parsing and the guard" do
    params = {delete_saved: false}

    expect(described_class.delete_saved_param(params)).to eq("false")
    expect(described_class.from_params(params, definition: definition).delete_saved).to eq(described_class.delete_saved_param(params))
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

RSpec.describe Querylane::Search, "delete saved searches" do
  let(:store) { double("saved-search store", all: []) }
  let(:context) { Querylane::Context.new(user: :alice) }
  let(:definition) do
    Querylane::Definition.build(:saved_people) do |definition|
      definition.index :employees, name: "people"
      definition.text :name, attributes: [:name], default: true
      definition.saved store: store
    end
  end

  def delete_saved(query: "", scope: Querylane::Scope.unrestricted(:employees))
    request = Querylane::Request.from_params({delete_saved: "12", search_query: query}, definition: definition)
    Querylane::Search.new(definition: definition, request: request, context: context, scope: scope, searcher: Object.new).call
  end

  it "passes the current context and selected id to the store" do
    expect(store).to receive(:delete).with(context: context, id: "12").and_return(true)

    expect(delete_saved).to have_attributes(notice: :deleted, query: "", rewritten: false, saved_searches: [])
  end

  it "does not mutate the store when access is denied" do
    expect(store).not_to receive(:delete)

    expect(delete_saved(scope: Querylane::Scope.denied)).to have_attributes(notice: nil)
  end

  it "does not report success for a missing or unowned entry" do
    allow(store).to receive(:delete).and_return(false)

    expect(delete_saved).to have_attributes(notice: :not_available)
  end

  it "keeps an invalid active query unchanged while deleting" do
    allow(store).to receive(:delete).and_return(true)

    expect(delete_saved(query: 'name:"unfinished')).to have_attributes(state: :invalid, notice: :deleted, query: 'name:"unfinished', rewritten: false)
  end

  it "reports store failure without claiming deletion succeeded" do
    allow(store).to receive(:delete).and_raise(IOError, "unavailable")

    expect(delete_saved).to have_attributes(notice: :store_failed)
  end
end
