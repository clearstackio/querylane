# frozen_string_literal: true

RSpec.describe Querylane::Query do
  def analyze(text) = described_class.analyze(TestSearch::DEFINITION, text)

  it "interprets bare tokens and resolves operators and aliases" do
    query = analyze("smith 5432 123456 status:Active")

    expect(query).to be_valid
    expect(query.nodes.map { |term| [term.kind, term.operator.key, term.value, term.interpreted] }).to eq([
      [:text, :name, "smith", false], [:filter, :last4, "5432", true], [:filter, :policy, "123456", true], [:flag, :is, :active, false]
    ])
  end

  it "normalizes before checking the format" do
    expect(analyze("ssn:123-45-6789").nodes.first.value).to eq("123456789")
    expect(analyze("last4:ab12").nodes.first.value).to eq("AB12")
  end

  it "suggests the operator the user meant" do
    expect(analyze("smith stauts:active").error.message).to eq("stauts: is not an operator. Did you mean status:?")
  end

  it "never repeats a sensitive value in an error" do
    error = analyze("ssn:12345").error

    expect(error.message).to eq("That value is not a valid ssn: value.")
    expect(error.range).to eq(0...9)
  end

  it "lists the values of a flag family" do
    expect(analyze("is:gone").error.message).to eq("gone is not a value of is:. Try active, pending, terminated.")
  end

  it "keeps names out of OR, NOT and groups" do
    expect(analyze("smith OR jones").error.message).to start_with("OR joins operators, not names")
    expect(analyze("-smith").error.message).to start_with("- and NOT apply to operators")
    expect(analyze("(smith is:active)").error.message).to start_with("Parentheses group operators")
  end

  it "allows one text operator per search" do
    expect(analyze("smith id:12345").error.message).to eq("Search name or id one at a time, or combine with ssn: or last4:.")
  end

  it "is blank for whitespace" do
    expect(analyze("   ")).to be_blank.and be_valid
  end

  it "leaves out the filters hint when the definition has no filters" do
    definition = Querylane::Definition.build(:texts) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.text :id, attributes: %i[memberid]
    end

    expect(described_class.analyze(definition, "smith id:12345").error.message).to eq("Search name or id one at a time.")
  end
end

RSpec.describe Querylane::Query, "error copy" do
  let(:definition) do
    Querylane::Definition.build(:copy) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :last, attribute: :last_name, normalize: :upcase, format: /\A[A-Z][A-Z -]*\z/, label: "Last name %{value}",
        invalid: "For part of a name, type plain words."
      d.filter :code, attribute: :code, format: /\A\d+\z/, invalid: "search.errors.code"
      d.filter :ssn, attribute: :ssn, sensitive: true, format: /\A\d{9}\z/, invalid: :"search.errors.ssn"
    end
  end

  def analyze(text) = described_class.analyze(definition, text)

  after { I18n.reload! }

  it "adds a filter's own sentence to the bad-value error" do
    expect(analyze("last:12345").error.message).to eq(%("12345" is not a valid last: value. For part of a name, type plain words.))
  end

  it "reads a filter's sentence from the locale when it is a key, and never repeats a sensitive value" do
    store_translations(search: {errors: {code: "Codes are digits.", ssn: "An SSN has nine digits."}})

    expect(analyze("code:abc").error.message).to eq(%("abc" is not a valid code: value. Codes are digits.))
    expect(analyze("ssn:12345").error.message).to eq("That value is not a valid ssn: value. An SSN has nine digits.")
  end

  it "takes every query error from querylane.errors, with the English text as default" do
    store_translations(querylane: {errors: {
      filter_value: "Bad %{key}: %{value}.", did_you_mean: "No %{key}:, try %{suggestion}:.", close_quote: "Quote!",
      text_in_or: "No names in OR."
    }})

    expect(analyze("last:12345").error.message).to eq("Bad last: 12345. For part of a name, type plain words.")
    expect(analyze("lst:smith").error.message).to eq("No lst:, try last:.")
    expect(analyze(%(smith "open)).error.message).to eq("Quote!")
    expect(analyze("smith OR jones").error.message).to eq("No names in OR.")
  end

  it "keeps the English defaults identical to the shipped locale file" do
    shipped = YAML.load_file(File.expand_path("../../config/locales/querylane.en.yml", __dir__)).dig("en", "querylane", "errors")

    expect(shipped.transform_keys(&:to_sym)).to eq(described_class::MESSAGES)
  end
end
