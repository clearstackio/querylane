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
end
