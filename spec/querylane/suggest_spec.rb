# frozen_string_literal: true

require "spec_helper"

RSpec.describe Querylane::Suggest do
  let(:definition) do
    Querylane::Definition.build(:suggest) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :policy, attribute: :policy_number, label: "Policy number %{value}"
      d.filter :last4, attribute: :id_last4
      d.flags :is, alias: :status, attribute: :status_label, values: {active: "Active records", openable: "Records you can open", terminated: "Terminated"}
    end
  end

  def words(text) = described_class.completions(definition, text).map(&:word)

  it "completes an operator from its first letters and searches people by the rest" do
    expect(described_class.completions(definition, "smith pol")).to eq([described_class::Completion.new("policy:", "Policy number")])
    expect(described_class.people_text(definition, "smith pol")).to eq("smith")
  end

  it "completes flag values after the key, by key or alias" do
    expect(words("lee is:")).to eq(["is:active", "is:openable", "is:terminated"])
    expect(words("lee status:te")).to eq(["status:terminated"])
    expect(words("lee sta")).to eq(["status:"])
    expect(described_class.people_text(definition, "lee is:")).to eq("lee")
  end

  it "treats words shorter than the minimum, with no filter, as too short" do
    short = Querylane::Definition.build(:short) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :team, attribute: :team
      d.min_text_length 3
    end
    query = ->(text) { Querylane::Query.analyze(short, text) }

    expect(query.call("al li").too_short?(3)).to be(true)
    expect(query.call("ali*").too_short?(3)).to be(false)
    expect(query.call("al*").too_short?(3)).to be(true)
    expect(query.call("al team:ops").too_short?(3)).to be(false)
  end

  it "offers nothing for names, single letters or finished words" do
    expect(words("smith")).to eq([])
    expect(words("smith p")).to eq([])
    expect(words("is:active")).to eq([])
    expect(described_class.people_text(definition, "smith 5432")).to eq("smith 5432")
  end
end
