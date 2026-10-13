# frozen_string_literal: true

RSpec.describe Querylane::Filter do
  let(:a) { described_class.eq(:team, "ops") }

  it "never widens with an empty OR: no grants match nothing" do
    expect(described_class.or).to be_a(Querylane::Filter::Nothing)
    expect(described_class.and(a, described_class.or)).to be_a(Querylane::Filter::Nothing)
  end

  it "applies boolean identities" do
    expect(described_class.or(described_class.everything, a)).to be_a(Querylane::Filter::Everything)
    expect(described_class.and(described_class.everything, a)).to eq(a)
    expect(described_class.not(described_class.everything)).to be_a(Querylane::Filter::Nothing)
    expect(described_class.not(described_class.nothing)).to be_a(Querylane::Filter::Everything)
  end
end
