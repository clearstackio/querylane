# frozen_string_literal: true

RSpec.describe Querylane::Searchers::Meilisearch::Expression do
  let(:filter) { Querylane::Filter }

  it "renders every node and escapes quotes and backslashes" do
    tree = filter.and(filter.in(:status, ["A", "P"]), filter.or(filter.null(:x), filter.missing(:x)), filter.eq(:name, %q(O'Brien \ x)))

    expect(described_class.render(tree)).to eq(%q{(status IN ['A', 'P']) AND ((x IS NULL) OR (x NOT EXISTS)) AND (name = 'O\'Brien \\\\ x')})
  end

  it "drops everything-filters from AND and renders nothing for an unrestricted search" do
    expect(described_class.render(filter.and(filter.everything, filter.everything))).to be_nil
    expect(described_class.render(filter.and(filter.everything, filter.eq(:a, 1)))).to eq("a = 1")
  end
end
