# frozen_string_literal: true

RSpec.describe Querylane::Definition, "new row and filter options" do
  def build(&block)
    described_class.build(:options) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.flags :is, attribute: :status_label, values: %i[active]
      d.option :exclude, "Exclude", "-is:active"
      block.call(d)
    end
  end

  it "keeps a row's hint and placeholder" do
    definition = build { |d| d.panel("Who") { |p| p.row "Name contains", :name, hint: "querylane.hints.name", placeholder: "Part of any name" } }

    expect(definition.panel_rows.first).to have_attributes(hint: "querylane.hints.name", placeholder: "Part of any name")
  end

  it "takes a placeholder only on an inputs row" do
    expect { build { |d| d.panel("Who") { |p| p.row "Status", :is, placeholder: "x" } } }.to raise_error(Querylane::ConfigurationError, /placeholder/)
    expect { build { |d| d.panel("Who") { |p| p.row nil, :exclude, placeholder: "x" } } }.to raise_error(Querylane::ConfigurationError, /placeholder/)
  end

  it "refuses as_words on a sensitive filter and a typed display on a masked one" do
    expect { build { |d| d.filter :ssn, attribute: :ssn, sensitive: true, as_words: true } }.to raise_error(Querylane::ConfigurationError, /as_words/)
    expect { build { |d| d.filter :ssn, attribute: :ssn, sensitive: true, display_value: :typed } }.to raise_error(Querylane::ConfigurationError, /typed/)
    expect { build { |d| d.filter :x, attribute: :x, display_value: :raw } }.to raise_error(Querylane::ConfigurationError, /display_value/)
  end

  it "still builds the structs from their earlier members" do
    filter = described_class::FilterOperator.new(:policy, "policy_number", false, nil, nil, "Policy %{value}", :none)
    row = described_class::PanelRow.new(label: "Policy", keys: [:policy], kind: :inputs, bare: false, masked: false, values: nil)

    expect(filter).to have_attributes(invalid: nil, as_words: false, display_value: :normalized)
    expect(row).to have_attributes(hint: nil, placeholder: nil)
  end

  it "keeps existing filters as they were" do
    filter = build { |d| d.filter :policy, attribute: :policy_number }.operator(:policy)

    expect(filter).to have_attributes(invalid: nil, as_words: false, display_value: :normalized)
  end
end

RSpec.describe Querylane::Copy do
  after { I18n.reload! }

  it "translates a locale key and keeps text as given" do
    store_translations(search: {hint: "From the locale"})

    expect(described_class.text(:"search.hint")).to eq("From the locale")
    expect(described_class.text("search.hint")).to eq("From the locale")
    expect(described_class.text("Exact last name, any case. E.g. SMITH.")).to eq("Exact last name, any case. E.g. SMITH.")
    expect(described_class.text(nil)).to be_nil
  end
end
