# frozen_string_literal: true

module Querylane
  # Runs one request: rewrite (facet toggle, chip ×) → analyze → compile →
  # searcher → Result. Requires a server-built Scope; fails closed.
  #
  #   Querylane::Search.new(definition: MEMBERS, request: request, scope: scope).call
  class Search
    PageRequest = Data.define(:compiled, :sort, :offset, :limit)
    # attribute: count values via the backend's facet distribution.
    # value_filters: {value => ->(index) { Filter }} counted one by one.
    CountRequest = Data.define(:key, :compiled, :attribute, :value_filters)

    # @param definition [Querylane::Definition]
    # @param request [Querylane::Request]
    # @param scope [Querylane::Scope]
    # @param context [Querylane::Context] facts for hooks (user, request)
    def initialize(definition:, request:, scope:, context: Context.new, searcher: nil, config: Querylane.configuration)
      raise MissingScopeError, "Pass the Querylane::Scope built for the current user" unless scope.is_a?(Scope)

      @definition = definition
      @request = request
      @context = context
      @scope = scope
      @searcher = searcher
      @config = config
    end

    # @return [Querylane::Result]
    def call
      @with_saved = @definition.saved_store.present?
      started = clock
      query = Query.analyze(@definition, @request.query, config: @config)
      query, rewritten = rewrite(query)
      @notice = save(query) if @request.save_search && !@scope.denied?
      return result(:first_load, query, rewritten) if query.valid? && query.blank?
      return result(:invalid, query, rewritten, error: query.error) unless query.valid?
      return result(:short, query, rewritten, chips: Chips.for(query)) if query.too_short?(@definition.min_text_length)
      return result(:denied, query, rewritten) if @scope.denied?

      response = searcher.search(definition: @definition, scope: hooked_scope, page: page_request(query), counts: count_requests(query))
      hits, merged = run_result_hooks(response.hits)
      group_totals = group_totals_for(hits)
      counts = response.counts
      facets = build_facets(query, counts || {})
      total, total_kind = total_of(response, counts)
      state = hits.empty? ? :empty : :ok
      instrument(state, response, started)
      result(state, query, rewritten, hits: hits, total: total, total_kind: total_kind, page_limit: response.page_limit,
        facets: facets, chips: Chips.for(query), timings: {total_ms: elapsed(started)}, merged: merged, group_totals: group_totals)
    rescue SearchUnavailable
      instrument(:unavailable, nil, started)
      result(:unavailable, query, rewritten || false)
    end

    # Every record of one group (a GroupToken in the request), any status,
    # within the scope and query-filter hooks. total: the group's records;
    # shown: "index:id" of the records the page already showed (see
    # Result#unshown_hits).
    #
    # @return [Querylane::Result] :unavailable when the token is invalid or expired
    def related
      started = clock
      value, shown = GroupToken.read(@definition, @request.group)
      return result(:denied, nil, false) if @scope.denied?
      return result(:unavailable, nil, false) if value.nil? || @definition.group.nil?

      group = @definition.group
      compiled = Compiler::Compiled.new(text: nil, text_attributes: [], matching: :all,
        filter_builder: ->(_index) { Filter.eq(group.attribute, value) })
      response = searcher.search(definition: @definition, scope: hooked_scope,
        page: PageRequest.new(compiled, group_sort(group), 0, group.limit), counts: [CountRequest.new(:total, compiled, nil, nil)])
      hits, = run_result_hooks(response.hits)
      instrument(:related, response, started)
      result(hits.empty? ? :empty : :ok, nil, false, hits: hits, total: response.counts&.dig(:total) || response.total, shown: shown)
    rescue SearchUnavailable
      result(:unavailable, nil, false)
    end

    # Suggestions for the request's text: operator completions for its last
    # word, and hits (people) for the rest. Never fails the page: a backend
    # error leaves only the completions.
    #
    # @return [Querylane::Result] state :ok/:empty/:first_load/:invalid/:unavailable, with completions
    def suggest
      completions = Suggest.completions(@definition, @request.query)
      whole = Query.analyze(@definition, @request.query, config: @config)
      typed = whole.valid? ? Preview.masked(whole) : nil
      query = Query.analyze(@definition, Suggest.people_text(@definition, @request.query), config: @config)
      return result(:invalid, query, false, completions: completions, typed: typed) unless query.valid?
      return result(:first_load, query, false, completions: completions, typed: typed) if query.blank? || query.too_short?(@definition.min_text_length) || @scope.denied?

      started = clock
      response = searcher.search(definition: @definition, scope: hooked_scope,
        page: PageRequest.new(compile(query), @definition.default_sort, 0, @config.suggest_records), counts: [])
      hits, = run_result_hooks(response.hits)
      instrument(:suggest, response, started)
      result(hits.empty? ? :empty : :ok, query, false, hits: hits, total: response.total, completions: completions, typed: typed)
    rescue SearchUnavailable
      result(:unavailable, query, false, completions: completions, typed: typed)
    end

    private

    def searcher = @searcher || @config.searcher

    # A group's records come back in the group's own order (default: relevance).
    def group_sort(group)
      group.order ? Definition::Sort.new(:group, "", group.order, false) : @definition.default_sort
    end

    # Records per group (value, down-cased) within the scope, so "more records"
    # shows only when there are more; nil when unknown (no group, or it failed).
    def group_totals_for(hits)
      group = @definition.group
      return if group.nil? || !searcher.respond_to?(:group_counts)

      values = hits.filter_map { |hit| @definition.group_value(hit.document) }.uniq
      searcher.group_counts(definition: @definition, scope: hooked_scope, attribute: group.attribute, values: values)
    rescue SearchUnavailable
      nil
    end

    # The required scope narrowed by every query-filter hook, per index.
    def hooked_scope
      hooks = @definition.hooks_for(:query_filter)
      return @scope if hooks.empty?

      extra = @scope.indexes.to_h do |index|
        filters = hooks.map do |hook|
          filter = guard(hook) { @definition.resolve_hook(hook).call(index: index, context: @context) }
          raise HookError, "query_filter hook #{hook.reference} must return a Querylane::Filter" unless filter_node?(filter)

          filter
        end
        [index, Filter.and(*filters)]
      end
      @scope.narrowed(extra)
    end

    # Runs results hooks in order. Each may keep a subset of the hits (in
    # order) or merge hits into one (via contributors); never add records.
    #
    # @return [Array(Array<Result::Hit>, Boolean)] hits and whether any were merged away
    def run_result_hooks(hits)
      allowed = hits.to_h { |hit| [[hit.index, hit.id], hit] }
      merged = false
      @definition.hooks_for(:results).each do |hook|
        output = guard(hook) { @definition.resolve_hook(hook).call(hits: hits.freeze, context: @context) }
        validate_result_hook!(hook, output, allowed)
        merged ||= hook.cardinality == :changing && output.sum { |hit| 1 + hit.contributors.size } != hits.sum { |hit| 1 + hit.contributors.size }
        merged ||= output.any? { |hit| hit.contributors.any? }
        hits = output
      end
      [hits, merged]
    end

    def validate_result_hook!(hook, output, allowed)
      valid = output.is_a?(Array) && output.all? do |hit|
        hit.is_a?(Result::Hit) && allowed.key?([hit.index, hit.id]) && hit.contributors.all? { |other| allowed.key?([other.index, other.id]) }
      end
      raise HookError, "results hook #{hook.reference} returned records it was not given" unless valid
      raise HookError, "results hook #{hook.reference} is :preserving but changed the hits" if hook.cardinality == :preserving && output.size != output.uniq.size
    end

    def guard(hook)
      yield
    rescue HookError
      raise
    rescue => error
      raise HookError, "#{hook.stage} hook #{hook.reference} failed (#{error.class.name})"
    end

    def filter_node?(filter)
      filter.class.name.to_s.start_with?("Querylane::Filter::")
    end

    # :exact, :capped (at the backend's maxTotalHits; may be higher) or
    # :estimated (counts unavailable).
    def total_of(response, counts)
      return [response.total, :estimated] unless counts&.key?(:total)

      cap = searcher.respond_to?(:max_total_hits) ? searcher.max_total_hits : nil
      total = counts[:total]
      [total, (cap && total >= cap) ? :capped : :exact]
    end

    def rewrite(query)
      return [Query.analyze(@definition, "", config: @config), query.source.present?] if @request.clear
      # "Fix it": apply the error's correction (only an invalid query has one).
      if @request.fix && !query.valid? && query.error.fix
        text = Rewriter.replace(query.source, query.error.range, query.error.fix)
        return [Query.analyze(@definition, text, config: @config), true]
      end
      # A saved search replaces the box whatever it holds (even an unfinished query).
      if @request.saved
        text = saved_text(@request.saved) || query.source
        return [Query.analyze(@definition, text, config: @config), text != query.source]
      end
      return [query, false] unless rewrite_requested?(query)

      text =
        if @request.compose
          Rewriter.compose(query, @request.compose)
        elsif @request.toggle
          Rewriter.toggle(query, *@request.toggle)
        elsif @request.widen
          Rewriter.without(query, @request.widen)
        elsif @request.instead
          chip_index, alternative_index = @request.instead
          chip = Chips.for(query).find { |candidate| candidate.index == chip_index }
          alternative = chip&.alternatives&.find { |candidate| candidate.index == alternative_index }
          alternative ? Rewriter.replace(query.source, chip.ranges.first, alternative.text) : query.source
        else
          chip = Chips.for(query).find { |candidate| candidate.index == @request.remove }
          chip ? Rewriter.remove(query.source, chip.ranges) : query.source
        end
      rewritten = Query.analyze(@definition, text, config: @config)
      [rewritten, text != query.source]
    end

    # Compiles with this request's matching strategy (hits and counts agree).
    def compile(query)
      compiled = Compiler.compile(query)
      @request.relax ? compiled.with(matching: :frequency) : compiled
    end

    def rewrite_requested?(query)
      query.valid? && @request.rewriting?
    end

    def page_request(query)
      PageRequest.new(compile(query), @request.sort, @request.offset, @request.per)
    end

    def count_requests(query)
      requests = [CountRequest.new(:total, compile(query), nil, nil)]
      @definition.facets.each do |facet|
        base = Query.analyze(@definition, Rewriter.without(query, facet), config: @config)
        next unless base.valid?

        requests << facet_count_request(facet, compile(base), Rewriter.ticked(query, facet))
      end
      requests
    end

    def facet_count_request(facet, compiled, ticked)
      if facet.flag
        flags = @definition.operator(facet.flag)
        return CountRequest.new(facet.key, compiled, flags.attribute, nil) if flags.attribute

        filters = @definition.flag_values(flags, facet.values).keys.to_h { |value| [value.to_s, ->(index) { @definition.flag_filter(flags, value, index: index) }] }
        CountRequest.new(facet.key, compiled, nil, filters)
      else
        operator = @definition.operator(facet.filter)
        extra = ticked.to_h { |value| [value, ->(_index) { Filter.eq(operator.attribute, value) }] }
        CountRequest.new(facet.key, compiled, operator.attribute, extra.presence)
      end
    end

    def build_facets(query, counts)
      @definition.facets.map do |facet|
        ticked = Rewriter.ticked(query, facet)
        found = counts[facet.key]
        next Result::Facet.new(facet.key, facet.label, [], true, false, facet.show, facet.search) unless found

        Result::Facet.new(facet.key, facet.label, facet_values(facet, found, ticked), false, truncated?(facet, found), facet.show, facet.search)
      end
    end

    # A filter facet's distribution may be cut at the backend's
    # maxValuesPerFacet (default 100); counts are then approximate.
    def truncated?(facet, found)
      facet.filter && found.size >= 100
    end

    def facet_values(facet, found, ticked)
      if facet.flag
        flags = @definition.operator(facet.flag)
        @definition.flag_values(flags, facet.values).map { |value, label| Result::FacetValue.new(value.to_s, label, found.fetch(value.to_s, 0), ticked.include?(value.to_s)) }
      else
        top = found.sort_by { |value, count| [-count, value.to_s] }.first(facet.top).map(&:first)
        operator = @definition.operator(facet.filter)
        (top | ticked).map do |value|
          label = operator.normalize ? operator.normalize.call(value) : value
          Result::FacetValue.new(value, label, found.fetch(value, 0), ticked.include?(value))
        end
      end
    end

    # Saves the query through the host's store unless it holds a sensitive term.
    #
    # @return [Symbol, nil] :saved, :refused or :store_failed; nil when there is nothing to save
    def save(query)
      store = @definition.saved_searches
      return if store.nil? || !query.valid? || query.blank?
      return :refused if Saving.refusal(query)

      store.create(context: @context, name: @request.saved_name.presence || query.source.first(80), query: query.source)
      :saved
    rescue => error
      saved_store_failed(error)
    end

    def saved_text(id)
      @definition.saved_searches&.use(context: @context, id: id)&.query
    rescue => error
      saved_store_failed(error)
      nil
    end

    def saved_list
      store = @definition.saved_searches
      store && Array(store.all(context: @context))
    rescue => error
      @notice = saved_store_failed(error)
      []
    end

    # A failing store never breaks the search; it is reported and shown as a notice.
    def saved_store_failed(error)
      ActiveSupport::Notifications.instrument("saved_search_failed.querylane", definition: @definition.name, error: error.class.name)
      :store_failed
    end

    def result(state, query, rewritten, **attributes)
      if @with_saved
        attributes = attributes.merge(saved_searches: saved_list, notice: @notice,
          save_refusal: (Saving.refusal(query) if query&.valid?))
      end
      if @request.options && query&.valid?
        panel = Rewriter.panel(query)
        attributes = attributes.merge(panel: panel, preview: Preview.for(@definition, query.source, panel.values, config: @config))
      end
      Result.new(definition: @definition, state: state, query: query&.source.to_s, request: @request, rewritten: rewritten, **attributes)
    end

    def instrument(state, response, started)
      ActiveSupport::Notifications.instrument("search.querylane", definition: @definition.name, state: state,
        backend_calls: response&.backend_calls, hits: response&.hits&.size, duration_ms: elapsed(started))
    end

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def elapsed(started) = ((clock - started) * 1000).round(1)
  end
end
