# frozen_string_literal: true

require "rails_helper"

RSpec.describe "querylane/_options_row", type: :request do
  let(:definition) do
    Querylane::Definition.build(:rows) do |d|
      d.index :x, name: "x"
      d.text :name, attributes: %i[full_name], default: true
      d.filter :ssn, attribute: :ssn, sensitive: true
      d.option :exclude, "Exclude terminated", "-is:terminated"
      d.panel "Who" do |p|
        p.row "Name contains", :name, placeholder: :"rows_spec.placeholder", hint: "rows_spec.hint"
        p.row "SSN", :ssn, placeholder: "Nine digits"
        p.row nil, :exclude, hint: "Leaves out ended records."
      end
    end
  end

  def render_row(row, held: {})
    SearchesController.render(partial: "querylane/options_row",
      locals: {row: row, values: {"options" => []}, held: held, definition: definition, id: "people"})
  end

  after { I18n.reload! }

  it "reads the placeholder and hint from the locale when given keys" do
    store_translations(rows_spec: {placeholder: "Part of any name", hint: "Plain words, any order."})
    html = Nokogiri::HTML(render_row(definition.panel_rows.first))

    expect(html.at_css("input")["placeholder"]).to eq("Part of any name")
    expect(html.at_css(".ql-options-hint").text).to eq("Plain words, any order.")
  end

  it "describes an options row's checkboxes by its hint" do
    html = Nokogiri::HTML(render_row(definition.panel_rows.last))

    expect(html.at_css("##{html.at_css("input")["aria-describedby"]}").text).to eq("Leaves out ended records.")
  end

  it "lets a masked row's held terms win over its own placeholder" do
    row = definition.panel_rows[1]

    expect(Nokogiri::HTML(render_row(row)).at_css("input")["placeholder"]).to eq("Nine digits")
    expect(Nokogiri::HTML(render_row(row, held: {"ssn" => "ssn:•••"})).at_css("input")["placeholder"]).to eq("In the box: ssn:•••")
  end

  it "draws no hint and no placeholder for a row without them" do
    plain = Querylane::Definition::PanelRow.new("Name contains", [:name], :inputs, false, false, nil)
    html = Nokogiri::HTML(render_row(plain))

    expect(html.at_css(".ql-options-hint")).to be_nil
    expect(html.at_css("input").attributes.keys).not_to include("placeholder", "aria-describedby")
  end
end
