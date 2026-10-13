# frozen_string_literal: true

RSpec.describe Querylane::Compiler do
  def compile(text) = described_class.compile(Querylane::Query.analyze(TestSearch::DEFINITION, text))

  def render(filter) = Querylane::Searchers::Meilisearch::Expression.render(filter)

  it "joins name words into one text query on the text attributes" do
    compiled = compile('smith "van der" 5432')

    expect(compiled).to have_attributes(text: 'smith "van der"', text_attributes: %w[full_name])
    expect(render(compiled.filter_for(:employees))).to eq("memberid_last4 = '5432'")
  end

  it "builds per-index filters for rules-based flags and boolean structure" do
    compiled = compile("(policy:1 OR policy:2) -has:combo")

    expect(render(compiled.filter_for(:employees))).to eq("((policy_number = '1') OR (policy_number = '2')) AND (NOT (combo = 'C'))")
    expect(render(compiled.filter_for(:ebmr))).to eq("((policy_number = '1') OR (policy_number = '2')) AND (NOT (combo = true))")
  end

  it "has no filter when only text was typed" do
    expect(compile("smith").filter_for(:employees)).to be_a(Querylane::Filter::Everything)
  end
end

RSpec.describe Querylane::Compiler, "wildcards" do
  it "drops a typed * from name words (prefix matching is built in)" do
    query = Querylane::Query.analyze(TestSearch::DEFINITION, "smi* jo*")

    expect(described_class.compile(query).text).to eq("smi jo")
  end
end
