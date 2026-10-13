# frozen_string_literal: true

RSpec.describe Querylane::Parser do
  def parse(text) = described_class.parse(text)

  it "reads words, key:value terms, quotes, negation, OR and groups with ranges" do
    root = parse('smith policy:123456 -is:terminated (policy:1 OR policy:2) name:"ann lee"')

    expect(root.nodes.map(&:class)).to eq([Querylane::Ast::Term, Querylane::Ast::Term, Querylane::Ast::Not, Querylane::Ast::Group, Querylane::Ast::Term])
    expect(root.nodes.first).to have_attributes(key: nil, value: "smith", range: 0...5)
    expect(root.nodes[3].nodes.first).to be_a(Querylane::Ast::Or)
    expect(root.nodes.last).to have_attributes(key: "name", value: "ann lee", quoted: true)
  end

  it "binds OR tighter than the implicit AND" do
    root = parse("policy:1 OR policy:2 is:active")

    expect(root.nodes.size).to eq(2)
    expect(root.nodes.first).to be_a(Querylane::Ast::Or)
  end

  it "lowercases keys and keeps character ranges for non-ASCII text" do
    root = parse("José STATUS:active")

    expect(root.nodes.last).to have_attributes(key: "status", range: 5...18)
  end

  {
    'smith "unclosed' => "Close the quote.",
    "policy: x" => "policy: needs a value.",
    "(policy:1" => "Add the closing ).",
    "policy:1)" => "Unexpected ).",
    "OR policy:1" => "OR needs a term on both sides.",
    "policy:1 OR" => "OR needs a term on both sides.",
    "()" => "Empty parentheses.",
    "((((a:1))))" => "Too many nested parentheses (3 at most)."
  }.each do |text, message|
    it "rejects #{text.inspect}" do
      expect { parse(text) }.to raise_error(Querylane::Parser::Error, message)
    end
  end

  it "bounds length and the number of terms" do
    expect { parse("a" * 257) }.to raise_error(Querylane::Parser::Error, /too long/)
    expect { parse((1..21).map { |n| "w#{n}" }.join(" ")) }.to raise_error(Querylane::Parser::Error, /Too many terms/)
  end
end

RSpec.describe Querylane::Parser, "error ranges" do
  {
    'ab "cd' => 3...6,
    "x (policy:1" => 2...11,
    "a OR" => 2...4,
    "é policy: " => 2...9,
    "café )" => 5...6
  }.each do |text, range|
    it "points at #{range} for #{text.inspect}" do
      expect { described_class.parse(text) }.to raise_error(Querylane::Parser::Error) { |error| expect(error.range).to eq(range) }
    end
  end

  it "keeps character (not byte) ranges after multibyte text" do
    root = described_class.parse("Zoë Ångström policy:1")

    expect(root.nodes.map(&:range)).to eq([0...3, 4...12, 13...21])
  end
end
