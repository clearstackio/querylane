# frozen_string_literal: true

RSpec.describe Querylane::Presenter, "group headings" do
  let(:definition) do
    Querylane::Definition.build(:headed) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.sort :best, default: true
      d.sort :name, by: {full_name: :asc}
      d.highlight :full_name
      d.group :person, order: {division: :asc}
    end
  end
  let(:view) { Class.new { def querylane_highlight(hit, attribute) = hit.document[attribute.to_s] }.new }

  def hit(id, person, name, division)
    Querylane::Result::Hit.new(index: :x, id: id, document: {"person" => person, "full_name" => name, "division" => division},
      formatted: {}, ranking_details: {})
  end

  def presenter(hits, sort: nil)
    request = Querylane::Request.new(definition: definition, sort: sort)
    described_class.new(Querylane::Result.new(definition: definition, state: :ok, query: "x", request: request, hits: hits), view)
  end

  # One person's records under two names: the group sits where "BAILEY, CMID"
  # came back, but its records read by division, "SALARY" first.
  let(:hits) do
    [hit("a", "p1", "BAILEY, CMID", "0005"), hit("b", "p2", "BAILEY, EFFIE", "0001"), hit("c", "p1", "BAILEY, SALARY", "0001")]
  end

  it "heads a sorted group with the record that placed it, keeping the group's record order" do
    page = presenter(hits, sort: "name")

    expect(page.groups.map { |group| page.title(group) }).to eq(["BAILEY, CMID", "BAILEY, EFFIE"])
    expect(page.groups.first.hits.map(&:id)).to eq(%w[c a])
  end

  it "heads a Best match group with its best-ranked record" do
    page = presenter(hits.reverse)

    expect(page.groups.map { |group| page.title(group) }).to eq(["BAILEY, SALARY", "BAILEY, EFFIE"])
    expect(page.groups.map(&:lead).map(&:id)).to eq(%w[c b])
  end

  it "leads a group built from hits alone with its first hit" do
    group = described_class::Group.new(nil, hits)

    expect(group.lead.id).to eq("a")
  end
end
