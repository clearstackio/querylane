# frozen_string_literal: true

RSpec.describe Querylane::Chips do
  def chips(text) = described_class.for(Querylane::Query.analyze(TestSearch::DEFINITION, text))

  it "labels each top-level term, masking sensitive values per operator" do
    expect(chips("smith 5432 is:active ssn:123456789 -is:terminated").map(&:label)).to eq([
      "Name contains smith", "Last four 5432", "Status Active", "SSN •••-••-6789", "Not Status Terminated"
    ])
  end

  it "masks a sensitive text operator fully" do
    expect(chips("id:12345").map(&:label)).to eq(["Member ID starting •••••"])
  end

  it "groups all name words into one chip with every range" do
    chip = chips("smith john").first

    expect(chip.ranges).to eq([0...5, 6...10])
  end
end

RSpec.describe Querylane::Chips, "alternatives" do
  it "offers the interpreter's other readings and rewrites to the chosen one" do
    stub_const("AltInterpreter", Module.new do
      module_function

      def call(token) = ([:last4, token] if token.match?(/\A\d{4}\z/))

      def alternatives(token) = [[:policy, token]]
    end)
    definition = Querylane::Definition.build(:alt) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :last4, attribute: :l4, label: "Last four %{value}"
      d.filter :policy, attribute: :policy, label: "Policy %{value}"
      d.interpreter "AltInterpreter"
    end
    query = Querylane::Query.analyze(definition, "smith 5432")
    chip = described_class.for(query).last

    expect(chip.alternatives.map(&:label)).to eq(["Policy 5432 instead"])
    expect(Querylane::Rewriter.replace(query.source, chip.ranges.first, chip.alternatives.first.text)).to eq("smith policy:5432")
  end
end
