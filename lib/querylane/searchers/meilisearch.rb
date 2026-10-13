# frozen_string_literal: true

module Querylane
  module Searchers
    # Default searcher: Meilisearch 1.13+ through the meilisearch gem 0.33.x
    # (the host adds `gem "meilisearch", "~> 0.33.0"`).
    #
    # Two HTTP calls per search (docs/spikes/meilisearch-1.13.md):
    # 1. a federated multi-search for the page of hits across all indexes;
    # 2. one batched multi-search for the exact total and every facet count
    #    (`page: 1, hits_per_page: 0` queries, facet distributions).
    class Meilisearch
      HIGHLIGHT_PRE = "\u0001"
      HIGHLIGHT_POST = "\u0002"
      # Meilisearch's default pagination.maxTotalHits; hosts may raise it in
      # index settings and pass `max_total_hits:`.
      DEFAULT_MAX_TOTAL_HITS = 1000

      Response = Data.define(:hits, :total, :counts, :page_limit, :backend_calls)

      # @param client [Meilisearch::Client, #call] a client, or a callable returning one
      # @param max_total_hits [Integer] the indexes' pagination.maxTotalHits
      def initialize(client:, max_total_hits: DEFAULT_MAX_TOTAL_HITS)
        require_gem!
        @client = client
        @max_total_hits = max_total_hits
      end

      # @return [Response]
      # @return [Response] counts is nil when the count batch failed (hits kept)
      def search(definition:, scope:, page:, counts:)
        indexes = searchable_indexes(definition, scope, page.compiled)
        return Response.new([], 0, empty_counts(counts), 0, 0) if indexes.empty?

        hits_response = call { client.multi_search(queries: page_queries(definition, scope, page, indexes), federation: {offset: page.offset, limit: page.limit}) }
        counts_read = count_batch(definition, scope, counts, indexes)
        Response.new(hits(hits_response, indexes), hits_response["estimatedTotalHits"].to_i, counts_read,
          (@max_total_hits / page.limit.to_f).ceil, counts_read ? 2 : 1)
      end

      # The cap Meilisearch applies to totalHits; a count equal to it may be higher.
      attr_reader :max_total_hits

      # How many records each group has within the scope: one facet count per
      # index on the group attribute, filtered to the page's group values.
      #
      # @param values [Array<String>] the group values on the page
      # @return [Hash{String => Integer}] keyed by the value, down-cased
      def group_counts(definition:, scope:, attribute:, values:)
        return {} if values.empty?

        indexes = scope.indexes.each_with_object({}) do |key, found|
          found[definition.index_name(key)] = key unless scope.filter_for(key).is_a?(Filter::Nothing)
        end
        return {} if indexes.empty?

        queries = indexes.map do |name, key|
          filter = Filter.and(scope.filter_for(key), Filter.in(attribute, values))
          {index_uid: name, q: "", filter: Expression.render(filter), facets: [attribute.to_s], page: 1, hits_per_page: 0}
        end
        call { client.multi_search(queries: queries) }.fetch("results").each_with_object(Hash.new(0)) do |answer, totals|
          answer.fetch("facetDistribution", {}).fetch(attribute.to_s, {}).each { |value, count| totals[value.to_s.downcase] += count }
        end
      end

      private

      def client = @client.respond_to?(:call) ? @client.call : @client

      def call
        yield
      rescue ::Meilisearch::ApiError, ::Meilisearch::CommunicationError, ::Meilisearch::TimeoutError => error
        raise SearchUnavailable, "Meilisearch #{error.class.name.demodulize}"
      end

      # Indexes whose scope and query can match something; the others are
      # never sent (a Nothing scope must not turn into an unrestricted query).
      def searchable_indexes(definition, scope, compiled)
        scope.indexes.each_with_object({}) do |key, indexes|
          next if Filter.and(scope.filter_for(key), compiled.filter_for(key)).is_a?(Filter::Nothing)

          indexes[definition.index_name(key)] = key
        end
      end

      def empty_counts(counts)
        counts.to_h { |count| [count.key, (count.key == :total) ? 0 : {}] }
      end

      # Exact totals and facet counts; nil if the batch fails (hits are kept).
      def count_batch(definition, scope, counts, indexes)
        queries, readers = count_plan(definition, scope, counts, indexes)
        return {} if queries.empty?

        read_counts(readers, call { client.multi_search(queries: queries).fetch("results") })
      rescue SearchUnavailable
        nil
      end

      def require_gem!
        require "meilisearch"
        return if Gem::Requirement.new("~> 0.33.0").satisfied_by?(Gem::Version.new(::Meilisearch::VERSION))

        raise ConfigurationError, "querylane's Meilisearch searcher needs the meilisearch gem ~> 0.33.0 (found #{::Meilisearch::VERSION})"
      rescue LoadError
        raise ConfigurationError, "Add gem \"meilisearch\", \"~> 0.33.0\" to use Querylane::Searchers::Meilisearch"
      end

      def base_query(name, key, scope, compiled)
        query = {index_uid: name, q: compiled.text.to_s, matching_strategy: compiled.matching.to_s}
        query[:attributes_to_search_on] = compiled.text_attributes if compiled.text
        combined = Filter.and(scope.filter_for(key), compiled.filter_for(key))
        filter = Expression.render(combined) unless combined.is_a?(Filter::Nothing)
        query[:filter] = filter if filter
        query
      end

      def page_queries(definition, scope, page, indexes)
        indexes.map do |name, key|
          query = base_query(name, key, scope, page.compiled).merge(
            attributes_to_highlight: definition.highlight, highlight_pre_tag: HIGHLIGHT_PRE, highlight_post_tag: HIGHLIGHT_POST,
            show_ranking_score_details: true
          )
          query[:attributes_to_retrieve] = definition.retrieve if definition.retrieve
          query[:sort] = page.sort.by.map { |attribute, direction| "#{attribute}:#{direction}" } if page.sort&.by
          query
        end
      end

      # Builds the count queries and, for each, how to read its answer.
      def count_plan(definition, scope, counts, indexes)
        queries = []
        readers = []
        counts.each do |count|
          indexes.each do |name, key|
            base = base_query(name, key, scope, count.compiled).merge(page: 1, hits_per_page: 0)
            if count.attribute.nil? && count.value_filters.nil?
              queries << base
              readers << [count.key, :total, nil]
            end
            if count.attribute
              queries << base.merge(facets: [count.attribute])
              readers << [count.key, :distribution, count.attribute]
            end
            count.value_filters&.each do |value, filter|
              combined = Filter.and(scope.filter_for(key), count.compiled.filter_for(key), filter.call(key))
              next if combined.is_a?(Filter::Nothing)

              queries << base.merge(filter: Expression.render(combined)).compact
              readers << [count.key, :value, value]
            end
          end
        end
        [queries, readers]
      end

      # Sums each count across indexes. Explicit per-value counts replace the
      # distribution's number for that value (they are exact for ticked values
      # outside the distribution's top values).
      def read_counts(readers, results)
        counts = {}
        explicit = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        readers.each_with_index do |(key, kind, detail), position|
          answer = results.fetch(position)
          case kind
          when :total then counts[key] = counts.fetch(key, 0) + answer["totalHits"].to_i
          when :distribution
            bucket = counts[key] ||= Hash.new(0)
            answer.fetch("facetDistribution", {}).fetch(detail, {}).each { |value, number| bucket[value.to_s] += number }
          when :value then explicit[key][detail] += answer["totalHits"].to_i
          end
        end
        explicit.each do |key, values|
          bucket = counts[key] ||= Hash.new(0)
          values.each { |value, number| bucket[value] = number unless bucket.key?(value) }
        end
        counts
      end

      def hits(response, indexes)
        response.fetch("hits").map do |hit|
          index = indexes.fetch(hit.dig("_federation", "indexUid"))
          document = hit.reject { |key, _| key.start_with?("_") }
          Result::Hit.new(index: index, id: document["id"].to_s, document: document, formatted: hit["_formatted"] || {},
            ranking_details: hit["_rankingScoreDetails"] || {})
        end
      end

      # Renders a Querylane::Filter as a Meilisearch filter expression.
      module Expression
        module_function

        # @return [String, nil] nil when the filter matches everything
        def render(filter)
          case filter
          when Filter::Everything, nil then nil
          when Filter::Nothing then raise ArgumentError, "Nothing filters are never sent; the index is skipped"
          when Filter::Raw then filter.expression
          when Filter::Eq then "#{filter.attribute} = #{value(filter.value)}"
          when Filter::In then "#{filter.attribute} IN [#{filter.values.map { |item| value(item) }.join(", ")}]"
          when Filter::Null then "#{filter.attribute} IS NULL"
          when Filter::Missing then "#{filter.attribute} NOT EXISTS"
          when Filter::Not then "NOT (#{render(filter.filter)})"
          when Filter::And then join(filter.filters, "AND")
          when Filter::Or then join(filter.filters, "OR")
          else raise ArgumentError, "Unknown filter #{filter.class}"
          end
        end

        def join(filters, operator)
          parts = filters.filter_map { |part| render(part) }
          return nil if parts.empty? && operator == "AND"

          parts.map { |part| "(#{part})" }.join(" #{operator} ")
        end

        def value(item)
          case item
          when true, false, Numeric then item.to_s
          else "'#{item.to_s.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }}'"
          end
        end
      end
    end
  end
end
