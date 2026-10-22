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

RSpec.describe Querylane::Chips, "exact name filters" do
  let(:definition) do
    Querylane::Definition.build(:names) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
      d.text :id, attributes: %i[memberid]
      d.filter :last, attribute: :last_name, normalize: ->(value) { value.upcase.delete(" '") }, label: "Last name %{value}",
        as_words: true, display_value: :typed
      d.filter :policy, attribute: :policy_number, normalize: :upcase, label: "Policy %{value}"
    end
  end

  def chips(text) = described_class.for(Querylane::Query.analyze(definition, text))

  it "shows a typed-display filter as typed and others normalized" do
    expect(chips(%(last:"van allen" policy:ab1)).map(&:label)).to eq(["Last name van allen", "Policy AB1"])
  end

  it "offers the typed value as words only for an opted-in filter at the top level" do
    expect(chips(%(smith last:o'brien policy:1 -last:jones)).map(&:as_words)).to eq([nil, "o'brien", nil, nil])
  end

  it "does not offer words while another text operator holds the words" do
    expect(chips("id:123 last:smith").map(&:as_words)).to eq([nil, nil])
  end

  it "offers words only when the rewritten query still fits the limits" do
    Querylane.configuration.max_terms = 3

    expect(chips(%(smith last:"a b")).last.as_words).to eq("a b")
    expect(chips(%(smith last:"a b c")).last.as_words).to be_nil
  end

  it "checks the words against the limits the query was read with" do
    config = Querylane::Configuration.new.tap { |custom| custom.max_terms = 2 }
    query = Querylane::Query.analyze(definition, %(last:"a b c"), config: config)

    expect(described_class.for(query).first.as_words).to be_nil
  end

  it "keeps the typed value even when the normalizer edits its argument" do
    definition = Querylane::Definition.build(:bang) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :last, attribute: :last_name, normalize: ->(value) { value.upcase! || value }, label: "Last name %{value}", display_value: :typed
    end

    expect(described_class.for(Querylane::Query.analyze(definition, "last:smith")).first.label).to eq("Last name smith")
  end
end
