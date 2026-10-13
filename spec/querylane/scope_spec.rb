# frozen_string_literal: true

RSpec.describe Querylane::Scope do
  it "requires at least one index and a filter for each" do
    expect { described_class.new({}) }.to raise_error(Querylane::MissingScopeError)
    expect { described_class.new(employees: nil) }.to raise_error(Querylane::MissingScopeError)
  end

  it "makes unrestricted access explicit" do
    expect(described_class.unrestricted(:employees).filter_for(:employees)).to be_a(Querylane::Filter::Everything)
  end
end

RSpec.describe Querylane::Presenter, "group order" do
  it "orders a group's records by the definition's group order" do
    definition = Querylane::Definition.build(:ordered) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.group :person, order: {policy: :asc, division: :desc}
    end
    hit = ->(id, policy, division) { Querylane::Result::Hit.new(index: :x, id: id, document: {"person" => "p1", "policy" => policy, "division" => division}, formatted: {}, ranking_details: {}) }
    result = Querylane::Result.new(definition: definition, state: :ok, query: "x", request: Querylane::Request.new(definition: definition),
      hits: [hit.call("a", "2", "1"), hit.call("b", "1", "1"), hit.call("c", "1", "9"), hit.call("d", "1", "1")])

    group = described_class.new(result, nil).groups.first

    expect(group.hits.map(&:id)).to eq(%w[c b d a])
  end
end
