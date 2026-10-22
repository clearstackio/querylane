# frozen_string_literal: true

# Creates the dummy app's two indexes on a real Meilisearch (MEILISEARCH_URL,
# MEILISEARCH_API_KEY). Specs needing it are tagged :meilisearch and skipped
# when the server is unreachable.
module MeilisearchFixtures
  STAFF = [
    {id: "s1", person: "p1", full_name: "SMITH, JOHN", id_last4: "5432", team: "billing", status_label: "active", started: "2016-01-01", combo: false},
    {id: "s2", person: "p1", full_name: "SMITH, JOHN", id_last4: "5432", team: "claims", status_label: "terminated", started: "2019-03-15", combo: true},
    {id: "s3", person: "p2", full_name: "SMITHERS, JANE", id_last4: "5432", team: "billing", status_label: "active", started: "2022-06-01", combo: false},
    {id: "s4", person: "p3", full_name: "LEE, ANN", id_last4: "1180", team: "claims", status_label: "active", started: "2020-02-01", combo: false},
    # One person under two names (a renamed record).
    {id: "s5", person: "p6", full_name: "MORGAN, JANE", id_last4: "7781", team: "billing", status_label: "active", started: "2021-01-01", combo: false},
    {id: "s6", person: "p6", full_name: "ADAMS, JANE", id_last4: "7781", team: "billing", status_label: "active", started: "2024-01-01", combo: false}
  ].freeze
  CONTRACTORS = [
    {id: "c1", person: "p4", full_name: "SMYTHE, ROBERT", id_last4: "5432", team: "ops", status_label: "active", started: "2023-11-15", combo: false},
    {id: "c2", person: "p5", full_name: "SMITH, HIDDEN", id_last4: "5432", team: "secret", status_label: "active", started: "2023-11-15", combo: false}
  ].freeze
  SETTINGS = {
    searchable_attributes: %w[full_name id_last4],
    filterable_attributes: %w[id_last4 team status_label person],
    sortable_attributes: %w[full_name],
    typo_tolerance: {"disableOnAttributes" => %w[id_last4]},
    faceting: {"sortFacetValuesBy" => {"*" => "count"}}
  }.freeze

  module_function

  def available?
    @available = DummySearch.client.healthy? if @available.nil?
    @available
  rescue
    @available = false
  end

  def load!
    client = DummySearch.client
    {staff: STAFF, contractors: CONTRACTORS}.each do |key, documents|
      name = DummySearch.index_name(key)
      client.delete_index(name) rescue nil # rubocop:disable Style/RescueModifier
      client.wait_for_task(client.create_index(name, primary_key: "id")["taskUid"])
      index = client.index(name)
      index.wait_for_task(index.update_settings(SETTINGS)["taskUid"])
      index.wait_for_task(index.add_documents(documents)["taskUid"])
    end
  end
end

RSpec.configure do |config|
  config.before(:suite) { MeilisearchFixtures.load! if MeilisearchFixtures.available? && RSpec.world.filtered_examples.values.flatten.any? { |example| example.metadata[:meilisearch] } }
  config.before(:each, :meilisearch) { skip "Meilisearch is not reachable" unless MeilisearchFixtures.available? }
end
