# frozen_string_literal: true

RSpec.describe Querylane::Search, "hooks" do
  let(:hit) { ->(id) { Querylane::Result::Hit.new(index: :employees, id: id, document: {"id" => id}, formatted: {}, ranking_details: {}) } }

  # A searcher that records the scope it was given and answers fixed hits.
  let(:searcher) do
    hits = [hit.call("1"), hit.call("2"), hit.call("3")]
    Class.new do
      attr_reader :scope

      define_method(:search) do |definition:, scope:, page:, counts:|
        @scope = scope
        Querylane::Searchers::Meilisearch::Response.new(hits, 3, {total: 3}, 10, 2)
      end
    end.new
  end

  def definition(&hooks)
    Querylane::Definition.build(:hooked) do |d|
      d.index :employees, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      hooks.call(d)
    end
  end

  def run(definition, context: Querylane::Context.new(user: :alice))
    request = Querylane::Request.new(definition: definition, query: "smith")
    described_class.new(definition: definition, request: request, scope: Querylane::Scope.new(employees: Querylane::Filter.eq(:company, "SI")),
      context: context, searcher: searcher).call
  end

  it "ANDs every query-filter hook into the scope, in order, with the context" do
    seen = []
    hook = ->(index:, context:) { seen << [index, context.user] and Querylane::Filter.eq(:visible, true) }
    run(definition { |d| d.hook :query_filter, hook })

    expect(seen).to eq([[:employees, :alice]])
    expect(Querylane::Searchers::Meilisearch::Expression.render(searcher.scope.filter_for(:employees))).to eq("(company = 'SI') AND (visible = true)")
  end

  it "lets results hooks keep a subset and marks merged pages" do
    keep_first = ->(hits:, context:) { [hits.first.with(contributors: hits[1..])] }
    result = run(definition { |d| d.hook :results, keep_first, cardinality: :changing })

    expect(result.hits.map(&:id)).to eq(["1"])
    expect(result).to have_attributes(merged: true, last_shown: 3)
  end

  it "refuses hooks that add records or fail, never showing unfiltered hits" do
    invent = ->(hits:, context:) { hits + [Querylane::Result::Hit.new(index: :employees, id: "999", document: {}, formatted: {}, ranking_details: {})] }
    broken = ->(index:, context:) { raise "boom" }

    expect { run(definition { |d| d.hook :results, invent }) }.to raise_error(Querylane::HookError, /not given/)
    expect { run(definition { |d| d.hook :query_filter, broken }) }.to raise_error(Querylane::HookError, /failed \(RuntimeError\)/)
  end

  it "rejects a query-filter hook that returns no filter" do
    expect { run(definition { |d| d.hook :query_filter, ->(index:, context:) {} }) }.to raise_error(Querylane::HookError, /must return/)
  end
end
