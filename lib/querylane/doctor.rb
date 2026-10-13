# frozen_string_literal: true

module Querylane
  # Checks that the host's Meilisearch indexes declare what a definition
  # needs. Reports problems; never changes settings (the host owns them).
  #
  #   Querylane::Doctor.check(MEMBERS, client: client).each { |problem| puts problem }
  module Doctor
    Problem = Data.define(:index, :message) do
      def to_s = "#{index}: #{message}"
    end

    module_function

    # @return [Array<Problem>]
    def check(definition, client:)
      definition.indexes.flat_map do |index|
        name = definition.index_name(index.key)
        settings = client.index(name).settings
        problems_for(definition, name, settings)
      end
    end

    def problems_for(definition, name, settings)
      searchable = settings.fetch("searchableAttributes", ["*"])
      filterable = settings.fetch("filterableAttributes", [])
      sortable = settings.fetch("sortableAttributes", [])
      no_typos = settings.dig("typoTolerance", "disableOnAttributes") || []
      problems = []
      definition.texts.flat_map(&:attributes).each do |attribute|
        problems << Problem.new(name, "#{attribute} is not searchable") unless searchable == ["*"] || searchable.include?(attribute)
      end
      definition.texts.select(&:sensitive).flat_map(&:attributes).each do |attribute|
        problems << Problem.new(name, "#{attribute} should have typo tolerance disabled") unless no_typos.include?(attribute)
      end
      (definition.filters.map(&:attribute) + definition.flags.filter_map(&:attribute)).uniq.each do |attribute|
        problems << Problem.new(name, "#{attribute} is not filterable") unless filterable.include?(attribute)
      end
      definition.sorts.filter_map(&:by).flat_map(&:keys).map(&:to_s).each do |attribute|
        problems << Problem.new(name, "#{attribute} is not sortable") unless sortable.include?(attribute)
      end
      sorted_by = settings.dig("faceting", "sortFacetValuesBy") || {}
      definition.facets.select(&:filter).each do |facet|
        attribute = definition.operator(facet.filter).attribute
        next if (sorted_by[attribute] || sorted_by["*"]) == "count"

        problems << Problem.new(name, "faceting.sortFacetValuesBy should be \"count\" for #{attribute} (top values)")
      end
      problems
    end
  end
end
