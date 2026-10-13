# frozen_string_literal: true

module Querylane
  # One search request, bounded and allowlisted against the definition.
  #
  # Params: query (Configuration#param_name), toggle ("facet:value"),
  # remove (chip index), clear, instead, widen, relax, compose (with
  # compose_submit), options, sort, page, per, revision.
  class Request
    attr_reader :fix, :saved, :save_search, :saved_name, :group, :query, :toggle, :remove, :clear, :instead, :widen, :relax, :compose, :options, :sort, :page, :per, :revision

    # @param params [ActionController::Parameters, Hash]
    # @param definition [Querylane::Definition]
    def self.from_params(params, definition:, config: Querylane.configuration)
      values = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      values = values.transform_keys(&:to_s)
      new(definition: definition, query: values[config.param_name.to_s], toggle: values["toggle"], remove: values["remove"], clear: values["clear"],
        instead: values["instead"], widen: values["widen"], relax: values["relax"],
        compose: (values["compose"] if values["compose_submit"].present?), options: values["options"],
        fix: values["fix"], group: values["group"], saved: values["saved"], save_search: values["save_search"], saved_name: values["saved_name"], sort: values["sort"], page: values["page"], per: values["per"], revision: values["revision"])
    end

    # instead: "chip.alternative" (use another reading of an interpreted term);
    # widen: a facet key (drop that facet's terms); relax: match fewer words.
    # compose: options-panel fields {"name" => "…", "policy" => "1 2", "is" => [...], "options" => [...]}
    # (applied only with compose_submit); options: open the options panel;
    # group: a GroupToken (all records of one group, see Search#related);
    # saved: a saved search id to run; save_search with saved_name: save the query.
    def initialize(definition:, query: nil, toggle: nil, remove: nil, clear: nil, instead: nil, widen: nil, relax: nil,
      compose: nil, options: nil, fix: nil, group: nil, saved: nil, save_search: nil, saved_name: nil, sort: nil, page: nil, per: nil, revision: nil)
      @query = query.to_s
      @clear = clear.present?
      @instead = instead.to_s.match(/\A(\d+)\.(\d+)\z/)&.captures&.map(&:to_i)
      @widen = definition.facet(widen)
      @relax = relax.present?
      @options = options.present?
      @group = group.presence
      @fix = fix.present?
      @saved = saved.to_s.presence&.first(64)
      @save_search = save_search.present?
      @saved_name = saved_name.to_s.squish.first(80)
      @compose = compose.is_a?(Hash) ? compose.to_h.transform_keys(&:to_s) : nil
      @toggle = parse_toggle(definition, toggle)
      @remove = (Integer(remove.to_s, exception: false) if remove.present?)
      @sort = definition.sort(sort)
      @per = definition.per_options.include?(per.to_i) ? per.to_i : definition.per_options.first
      @page = rewriting? ? 1 : [page.to_i, 1].max
      @revision = [revision.to_i, 0].max
    end

    # @return [Integer] records skipped before this page
    def offset = (page - 1) * per

    # Whether this request asks the server to rewrite the query text.
    def rewriting? = (@toggle || @remove || @clear || @instead || @widen || @compose || @saved) ? true : false

    private

    # @return [Array(Querylane::Definition::Facet, String), nil]
    def parse_toggle(definition, toggle)
      key, value = toggle.to_s.split(":", 2)
      facet = definition.facet(key) if value.present?
      [facet, value] if facet
    end
  end
end
