# frozen_string_literal: true

RSpec.describe Querylane::Rewriter do
  let(:definition) { TestSearch::DEFINITION }

  def query(text) = Querylane::Query.analyze(definition, text)

  def toggle(text, facet, value) = described_class.toggle(query(text), definition.facet(facet), value)

  it "ticks and unticks a flag value" do
    expect(toggle("smith", :status, "active")).to eq("smith is:active")
    expect(toggle("smith is:active", :status, "active")).to eq("smith")
  end

  it "keeps several values of one facet in one canonical OR group" do
    expect(toggle("smith is:active", :status, "pending")).to eq("smith (is:active OR is:pending)")
    expect(toggle("smith (is:active OR is:pending)", :status, "active")).to eq("smith is:pending")
  end

  it "treats aliases, duplicates and interpreted values as canonical" do
    expect(described_class.ticked(query("status:active is:active 123456"), definition.facet(:status))).to eq(["active"])
    expect(described_class.ticked(query("123456"), definition.facet(:policy))).to eq(["123456"])
  end

  it "leaves negated and mixed groups alone and appends the canonical term" do
    expect(toggle("-is:active", :status, "active")).to eq("-is:active is:active")
    expect(toggle("(is:active OR policy:1)", :status, "active")).to eq("(is:active OR policy:1) is:active")
  end

  it "builds the facet's counting base without its own terms" do
    expect(described_class.without(query("smith is:active policy:1"), definition.facet(:status))).to eq("smith policy:1")
  end

  it "removes ranges and tidies spaces" do
    expect(described_class.remove("smith  5432 is:active", [7...11])).to eq("smith is:active")
  end
end

RSpec.describe Querylane::Rewriter, "verbatim text" do
  let(:definition) do
    Querylane::Definition.build(:codes) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :code, attribute: :code, normalize: :upcase
      d.flags :is, attribute: :status_label, values: %i[active pending]
      d.facet :status, flag: :is
      d.facet :code, filter: :code
    end
  end

  def query(text) = Querylane::Query.analyze(definition, text)

  it "keeps quoted values exactly as typed when rewriting" do
    expect(described_class.toggle(query(%(code:"A  B" is:active)), definition.facet(:status), "pending")).to eq(%(code:"A  B" (is:active OR is:pending)))
  end

  it "normalizes a toggled value before comparing, so it can be unticked" do
    expect(described_class.toggle(query("code:ab"), definition.facet(:code), "ab")).to eq("")
  end

  it "rejects flags with both attribute and rules" do
    expect {
      Querylane::Definition.build(:bad) do |d|
        d.index :x, name: "x"
        d.text :name, attributes: %i[n]
        d.flags :is, attribute: :a, rules: "X", values: %i[a]
      end
    }.to raise_error(Querylane::ConfigurationError, /not both/)
  end
end

RSpec.describe Querylane::Rewriter, "options panel" do
  let(:definition) do
    Querylane::Definition.build(:panel) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.text :id, attributes: %i[memberid]
      d.filter :last4, attribute: :id_last4, format: /\A\d{4}\z/
      d.filter :policy, attribute: :policy_number
      d.flags :is, attribute: :status_label, values: %i[active pending terminated]
      d.option :exclude_terminated, "Exclude terminated", "-is:terminated"
      d.interpreter ->(token) { [:last4, token] if token.match?(/\A\d{4}\z/) }
      d.panel "Who" do |p|
        p.row "Name contains", :name
        p.row "ID or last four", :id, :last4, bare: true
      end
      d.panel "Where" do |p|
        p.row "Policy", :policy
        p.row "Status", :is
        p.row nil, :exclude_terminated
      end
    end
  end

  def query(text) = Querylane::Query.analyze(definition, text)

  it "reads fields from the query and keeps what it cannot show" do
    panel = described_class.panel(query(%(agrawal 5432 (policy:1 OR policy:2) is:active -is:terminated (policy:3 OR is:pending))))

    expect(panel.values).to eq("name" => "agrawal", "id_or_last4" => "5432", "policy" => "1 2", "is" => ["active"],
      "options" => ["exclude_terminated"])
    expect(panel.kept).to eq("(policy:3 OR is:pending)")
  end

  it "writes the query from fields, keeping the rest as typed" do
    text = described_class.compose(query("(policy:3 OR is:pending) smith"), {"name" => %(agrawal "van der"), "id_or_last4" => "5432",
      "policy" => "123456 900001", "is" => ["active", "bogus"], "options" => ["exclude_terminated"]})

    expect(text).to eq(%[(policy:3 OR is:pending) agrawal "van der" 5432 (policy:123456 OR policy:900001) is:active -is:terminated])
  end

  it "round-trips a query the panel fully shows" do
    source = "agrawal policy:123456 is:active -is:terminated"
    q = query(source)

    expect(described_class.compose(q, described_class.panel(q).values)).to eq(source)
  end

  it "lays out every operator in one group by default" do
    plain = Querylane::Definition.build(:plain) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.flags :is, attribute: :status_label, values: %i[active]
    end

    expect(plain.panel_rows.map { |row| [row.keys, row.kind] }).to eq([[[:name], :inputs], [[:is], :flags]])
  end

  it "refuses a panel row that names nothing" do
    expect do
      Querylane::Definition.build(:bad) do |d|
        d.index :x, name: "x"
        d.text :name, attributes: %i[full_name]
        d.panel("Who") { |p| p.row "Ghost", :ghost }
      end
    end.to raise_error(Querylane::ConfigurationError, /ghost/)
  end

  it "masks sensitive values in the preview" do
    sensitive = Querylane::Definition.build(:masked) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :ssn, attribute: :memberid, sensitive: true, normalize: :digits
    end

    preview = Querylane::Preview.for(sensitive, "smith", {"name" => "smith", "ssn" => "123-45-6789"})

    expect(preview.text).to eq("smith ssn:•••••••••")
    expect(preview.kept).to eq("")
  end

  it "refuses to save sensitive terms, typed or interpreted, at any depth" do
    sensitive = Querylane::Definition.build(:saving) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :last4, attribute: :id_last4, sensitive: true, format: /\A\d{4}\z/, mask: :none
      d.filter :ssn, attribute: :memberid, sensitive: true, normalize: :digits
      d.filter :team, attribute: :team
      d.interpreter ->(token) { [:last4, token] if token.match?(/\A\d{4}\z/) }
    end
    refusal = ->(text) { Querylane::Saving.refusal(Querylane::Query.analyze(sensitive, text)) }

    expect(refusal.call("smith team:ops")).to be_nil
    expect(refusal.call("smith 5432")).to eq(Querylane::Saving::Refusal.new("5432", "Last4", "smith"))
    expect(refusal.call("team:ops -(ssn:123456789)").value).to eq("•••••••••")
  end
end

RSpec.describe Querylane::Rewriter, "facets sharing a flag family" do
  let(:definition) do
    Querylane::Definition.build(:shared) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.flags :is, attribute: :status_label, values: %i[active terminated openable not_openable]
      d.facet :status, flag: :is, values: %i[active terminated]
      d.facet :can_open, flag: :is, values: %i[openable not_openable]
    end
  end

  def query(text) = Querylane::Query.analyze(definition, text)

  it "ticks and toggles each facet's own values only" do
    q = query("smith is:openable is:active")

    expect(described_class.ticked(q, definition.facet(:status))).to eq(["active"])
    expect(described_class.ticked(q, definition.facet(:can_open))).to eq(["openable"])
    expect(described_class.toggle(q, definition.facet(:status), "terminated")).to eq("smith is:openable (is:active OR is:terminated)")
    expect(described_class.toggle(q, definition.facet(:status), "openable")).to eq("smith is:openable is:active")
  end

  it "refuses a facet value its flag family lacks" do
    expect do
      Querylane::Definition.build(:bad) do |d|
        d.index :x, name: "x"
        d.text :name, attributes: %i[full_name]
        d.flags :is, attribute: :status_label, values: %i[active]
        d.facet :status, flag: :is, values: %i[ghost]
      end
    end.to raise_error(Querylane::ConfigurationError, /ghost/)
  end
end

RSpec.describe Querylane::Rewriter, "options panel quoting and sensitive fields" do
  let(:definition) do
    Querylane::Definition.build(:quoting) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :team, attribute: :team
      d.filter :ssn, attribute: :memberid, sensitive: true, normalize: :digits
      d.filter :last4, attribute: :id_last4, format: /\A\d{4}\z/
      d.interpreter ->(token) { [:last4, token] if token.match?(/\A\d{4}\z/) }
    end
  end

  def query(text) = Querylane::Query.analyze(definition, text)

  it "round-trips quoted values unchanged" do
    [%(team:"New York"), %("a \\"b\\" c"), %("5432" smith), %((team:"New York" OR team:ops))].each do |source|
      q = query(source)
      expect(described_class.compose(q, described_class.panel(q).values)).to eq(source), source
    end
  end

  it "never reads a sensitive value into a field, keeps it in the box and shows it masked" do
    panel = described_class.panel(query("smith ssn:123456789"))

    expect(panel.values["ssn"]).to eq("")
    expect(panel.kept).to eq("ssn:123456789")
    expect(panel.held).to eq("ssn" => "ssn:•••••••••")
  end
end

RSpec.describe Querylane::Rewriter, "panel rows sharing a flag family" do
  let(:definition) do
    Querylane::Definition.build(:split) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.flags :is, attribute: :status_label, values: %i[active terminated openable]
      d.panel "Status" do |p|
        p.row "Status", :is, values: %i[active terminated]
        p.row "Can open", :is, values: %i[openable]
      end
    end
  end

  it "keeps each row's selection" do
    q = Querylane::Query.analyze(definition, "is:active is:openable")

    expect(described_class.compose(q, described_class.panel(q).values)).to eq("is:active is:openable")
  end

  it "refuses a row value the family lacks" do
    expect do
      Querylane::Definition.build(:bad) do |d|
        d.index :x, name: "x"
        d.text :name, attributes: %i[full_name]
        d.flags :is, attribute: :status_label, values: %i[active]
        d.panel("Status") { |p| p.row "Status", :is, values: %i[ghost] }
      end
    end.to raise_error(Querylane::ConfigurationError, /ghost/)
  end
end

RSpec.describe Querylane::Saving do
  let(:definition) do
    Querylane::Definition.build(:refuse) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :ssn, attribute: :memberid, sensitive: true, format: /\A\d{9}\z/
      d.interpreter ->(token) { [:ssn, token] if token.match?(/\A\d{9}\z/) }
    end
  end

  it "saves a value given to a non-sensitive filter even when it looks like one" do
    with_div = Querylane::Definition.build(:div) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :last4, attribute: :id_last4, sensitive: true
      d.filter :div, attribute: :division
      d.interpreter ->(token) { [:last4, token] if token.match?(/\A\d{4}\z/) }
    end

    expect(described_class.refusal(Querylane::Query.analyze(with_div, "smith div:0001"))).to be_nil
    expect(described_class.refusal(Querylane::Query.analyze(with_div, %(smith "0001")))).not_to be_nil
  end

  it "refuses a value the box would read as sensitive even when typed as a name" do
    [%("123456789" smith), "name:123456789 smith"].each do |text|
      refusal = described_class.refusal(Querylane::Query.analyze(definition, text))

      expect(refusal).to have_attributes(value: "•••••••••", rest: "smith"), text
    end
  end
end

RSpec.describe Querylane::Rewriter, "as words" do
  let(:definition) do
    Querylane::Definition.build(:names) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :last, attribute: :last_name, normalize: ->(value) { value.upcase.delete(" ") }, as_words: true, display_value: :typed
      d.filter :policy, attribute: :policy_number
      d.interpreter ->(token) { [:policy, token] if token.match?(/\A\d+\z/) }
      d.panel("Who") { |p| p.row "Last name", :last }
    end
  end

  def query(text) = Querylane::Query.analyze(definition, text)

  def as_words(text, index)
    analyzed = query(text)
    described_class.as_words(analyzed, Querylane::Chips.for(analyzed).find { |chip| chip.index == index })
  end

  it "replaces the filter term with its typed value as plain words" do
    expect(as_words("smith last:smiht is", 1)).to eq("smith smiht is")
    expect(as_words(%(last:"van allen" policy:1), 0)).to eq("van allen policy:1")
  end

  it "quotes words the parser would read as syntax" do
    expect(as_words(%(last:"OR -x a:b (c)"), 0)).to eq(%("OR" "-x" "a:b" "(c)"))
  end

  it "quotes words the interpreter would read as an operator" do
    expect(as_words(%(last:"smith 1234"), 0)).to eq(%(smith "1234"))
    expect(query(as_words(%(last:"smith 1234"), 0)).text_terms.map(&:value)).to eq(%w[smith 1234])
  end

  it "keeps the words apart from a neighbour typed without a space" do
    expect(as_words(%(last:"smith"policy:1), 0)).to eq("smith policy:1")
  end

  it "leaves the query alone for a chip that does not offer it" do
    expect(as_words("smith policy:1", 1)).to eq("smith policy:1")
    expect(described_class.as_words(query("smith"), nil)).to eq("smith")
  end

  it "shows and writes a typed-display filter as typed in the options panel" do
    analyzed = query(%(last:"van allen"))

    expect(described_class.panel(analyzed).values["last"]).to eq(%("van allen"))
    expect(described_class.compose(analyzed, {"last" => "o'brien smith"})).to eq("(last:o'brien OR last:smith)")
  end
end
