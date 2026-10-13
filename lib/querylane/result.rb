# frozen_string_literal: true

module Querylane
  # Everything a page needs to render one search.
  #
  # state: :first_load (nothing typed), :short (words too short to search),
  # :ok, :empty (no hits), :invalid
  # (query error), :unavailable (backend failed; fail closed).
  # total_kind: :exact, :capped (backend cap reached; may be higher),
  # :estimated (counts unavailable).
  class Result
    # contributors: other hits a results hook merged into this one.
    Hit = Data.define(:index, :id, :document, :formatted, :ranking_details, :contributors) do
      def initialize(index:, id:, document:, formatted:, ranking_details:, contributors: [])
        super
      end
    end
    FacetValue = Data.define(:value, :label, :count, :ticked)
    # show: values shown before "Find…"; search: whether the facet has a "Find…" box.
    Facet = Data.define(:key, :label, :values, :failed, :approximate, :show, :search) do
      def initialize(key:, label:, values:, failed:, approximate:, show: nil, search: false)
        super
      end
    end

    attr_reader :definition, :state, :query, :rewritten, :revision, :hits, :total, :total_kind,
      :page, :per, :page_limit, :sort, :facets, :chips, :error, :timings, :merged, :relaxed, :panel, :preview, :shown, :completions, :typed, :saved_searches, :save_refusal, :notice, :group_totals

    def initialize(definition:, state:, query:, request:, rewritten: false, hits: [], total: 0, total_kind: :exact,
      page_limit: nil, facets: [], chips: [], error: nil, timings: {}, merged: false, panel: nil, preview: nil,
      shown: [], completions: [], typed: nil, saved_searches: nil, save_refusal: nil, notice: nil, group_totals: nil)
      @definition = definition
      @state = state
      @query = query
      @rewritten = rewritten
      @revision = request.revision
      @page = request.page
      @per = request.per
      @sort = request.sort
      @hits = hits
      @total = total
      @total_kind = total_kind
      @page_limit = page_limit
      @facets = facets
      @chips = chips
      @error = error
      @timings = timings
      @merged = merged
      @relaxed = request.relax
      @panel = panel
      @preview = preview
      @shown = shown
      @completions = completions
      # suggestions: the whole typed text, sensitive values masked (for display)
      @typed = typed
      # saved searches: the user's list (nil without a store), why this query
      # cannot be saved, and a one-line notice (:saved, :refused, :store_failed)
      @saved_searches = saved_searches
      @save_refusal = save_refusal
      @notice = notice
      # records per group value (down-cased) within the scope, or nil when unknown
      @group_totals = group_totals
    end

    # Whether the options panel is open (it needs a valid query to read).
    def options_open? = !panel.nil?

    # Facets with ticked values: an empty search can offer to widen them.
    def widenable_facets = facets.select { |facet| facet.values.any?(&:ticked) }

    def ok? = state == :ok

    # Whether the query is one of the user's saved searches (the Saved star fills).
    def saved_active? = query.present? && Array(saved_searches).any? { |saved| saved.query == query }

    # A group's hits the page did not already show ("more records").
    def unshown_hits = hits.reject { |hit| shown.include?("#{hit.index}:#{hit.id}") }

    # @return [Integer]
    def pages
      count = (total.to_f / per).ceil
      page_limit ? [count, page_limit].min : count
    end

    def first_shown = hits.empty? ? 0 : ((page - 1) * per) + 1

    # Records shown on this page before a results hook merged any.
    def last_shown = ((page - 1) * per) + hits.sum { |hit| 1 + hit.contributors.size }
  end
end
