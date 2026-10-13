# frozen_string_literal: true

# The dummy app's search: people in two indexes with a status and a team.
module DummySearch
  module_function

  def configure!
    Querylane.configure do |config|
      config.searcher = -> { Querylane::Searchers::Meilisearch.new(client: DummySearch.client) }
    end
  end

  def client
    Meilisearch::Client.new(ENV.fetch("MEILISEARCH_URL", "http://localhost:7700"), ENV["MEILISEARCH_API_KEY"])
  end

  def index_name(key) = "querylane_spec_#{key}"

  def definition
    @definition ||= Querylane::Definition.build(:people) do |d|
      d.index :staff, name: index_name(:staff)
      d.index :contractors, name: index_name(:contractors)
      d.text :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
      d.filter :last4, attribute: :id_last4, sensitive: true, format: /\A\d{4}\z/, label: "Last four %{value}", mask: :none
      d.filter :team, attribute: :team, label: "Team %{value}"
      d.flags :is, alias: :status, attribute: :status_label, label: "Status", values: {active: "Active", terminated: "Terminated"}
      d.facet :status, flag: :is
      d.facet :team, filter: :team, top: 5, show: 1, search: true
      d.sort :best, label: "Best match", default: true
      d.sort :name, label: "Name A–Z", by: {full_name: :asc}
      d.per 2, 10
      d.interpreter ->(token) { [:last4, token] if token.match?(/\A\d{4}\z/) }
      d.group :person
      d.parked :first
      d.min_text_length 3
      d.saved store: "MemorySavedSearches"
      d.option :exclude_terminated, "Exclude terminated", "-is:terminated"
      d.panel "Who" do |p|
        p.row "Name contains", :name
        p.row "Last four", :last4
      end
      d.panel "Where and status" do |p|
        p.row "Team", :team
        p.row "Status", :is
        p.row nil, :exclude_terminated
      end
    end
  end
end
