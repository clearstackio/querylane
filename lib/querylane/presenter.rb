# frozen_string_literal: true

require "digest"

module Querylane
  # How a host's records look in the gem's result rows. Subclass and override:
  # Ruby decides (this class), the gem's partials draw (querylane/_rows,
  # _group, _record, _outcome). Hits are grouped on the server by `group_key`
  # (e.g. one person); the key itself never reaches the page.
  #
  #   class MemberPresenter < Querylane::Presenter
  #     def columns = [Column.new(:policy, "Policy", 80)]
  #     def group_key(hit) = hit.document["memberid"]
  #     def cells(hit) = [Cell.new(hit.document["policy_number"], :strong)]
  #     def outcome(hit) = Action.new("Open", select_path, {id: hit.id}, :primary)
  #   end
  class Presenter
    # A record lane; width in pixels, nil to take the remaining space.
    Column = Data.define(:key, :label, :width)
    # One lane's value; style :strong, :muted or nil.
    Cell = Data.define(:text, :style)
    # tone: :success, :warning, :danger, :info, :neutral.
    Badge = Data.define(:text, :tone)
    # A button that opens the record (full-page POST, outside the frame).
    Action = Data.define(:label, :url, :params, :style)
    # Why a record cannot be opened, with an optional link to go instead.
    # more: further reasons, shown on request ("+2 more").
    Reason = Data.define(:text, :link_label, :link_url, :more) do
      def initialize(text:, link_label: nil, link_url: nil, more: [])
        super
      end
    end
    # lead: the hit that placed the group on the page (the first of its hits
    # to come back, in the page's sort); hits may be reordered after it.
    Group = Data.define(:key, :hits, :lead) do
      def initialize(key:, hits:, lead: hits.first)
        super
      end
    end
    # A group in suggestions: a short detail, its status, and what choosing it
    # does (an Action opens it; nil runs the full search).
    Suggestion = Data.define(:detail, :badge, :action)

    attr_reader :result, :view, :id

    # @param result [Querylane::Result]
    # @param view [ActionView::Base] for routes and helpers
    # @param id [String, nil] the widget id (frames and the search form)
    def initialize(result, view, id: nil)
      @result = result
      @view = view
      @id = id&.to_s
    end

    # @return [Array<Column>]
    def columns = []

    # Header of the last lane.
    def outcome_label = "Open"

    # Header of the status lane, nil for no status lane.
    def status_label = "Status"

    # Hits sharing a key form one group; nil keeps a hit on its own. Default:
    # the definition's `group` attribute. An override must return that
    # attribute's value (it is what "more records" searches for).
    def group_key(hit) = result.definition.group_value(hit.document)

    # An opaque token for loading every record of the group ("more records",
    # preview), or nil when the group cannot be loaded.
    #
    # @return [String, nil]
    def group_token(group)
      value = group_key(group.hits.first)
      return if value.nil? || result.definition.group.nil?

      GroupToken.write(result.definition, value, group.hits.map { |hit| "#{hit.index}:#{hit.id}" })
    end

    # How many of the group's records the page does not show, or nil when
    # unknown. "More records" shows only when this is positive.
    #
    # @return [Integer, nil]
    def more_count(group)
      value = group_key(group.hits.first)
      return if value.nil? || result.group_totals.nil?

      shown = group.hits.sum { |hit| 1 + hit.contributors.size }
      more = result.group_totals.fetch(value.to_s.downcase, 0) - shown
      more if more.positive?
    end

    # @return [String] the id of the group's "more records" frame
    def related_frame_id(group) = "#{id}-related-#{record_key(group.hits.first)}"

    # @return [Array<Group>] in hit order: each group sits where its first hit
    #   came back (best-ranked, or first in the chosen sort), which leads it
    def groups
      order = []
      grouped = {}
      result.hits.each_with_index do |hit, position|
        key = group_key(hit) || "__#{position}"
        order << key unless grouped.key?(key)
        (grouped[key] ||= []) << hit
      end
      order.map do |key|
        hits = grouped.fetch(key)
        Group.new(key: key, hits: order_records(hits), lead: hits.first)
      end
    end

    # A group's records in the definition's group order (the order "more
    # records" and the preview use); unchanged without one. The lead record
    # still decides where the group sits on the page and what it is called.
    def order_records(hits)
      order = result.definition.group&.order
      return hits if order.nil? || hits.one?

      hits.each_with_index.sort do |(left, first), (right, second)|
        compared = compare_records(left, right, order)
        compared.zero? ? first <=> second : compared
      end.map(&:first)
    end

    def compare_records(left, right, order)
      order.each do |attribute, direction|
        compared = left.document[attribute].to_s <=> right.document[attribute].to_s
        return (direction.to_sym == :desc) ? -compared : compared unless compared.zero?
      end
      0
    end

    # Group heading (HTML-safe); default: the lead record's first highlighted
    # text attribute, so headings follow the page's order (Name A–Z reads in
    # name order even when one person's records carry different names).
    def title(group)
      attribute = result.definition.highlight.first
      view.querylane_highlight(group.lead, attribute)
    end

    # Secondary heading next to the title (HTML-safe or plain), or nil.
    def subtitle(group) = nil

    # Why the group matched, or nil.
    def note(group) = nil

    # @return [Array<Cell>] one per column
    def cells(hit) = []

    # @return [Badge, nil]
    def status(hit) = nil

    # @return [Array<Badge>] small flags after the status lane
    def flags(hit) = []

    # @return [Action, Reason, nil]
    def outcome(hit) = nil

    # How a group appears in suggestions. Default: its record count, the first
    # record's status, and its Action when exactly one record can be opened.
    #
    # @return [Suggestion]
    def suggestion(group)
      actions = group.hits.map { |hit| outcome(hit) }.grep(Action)
      Suggestion.new(view.t("querylane.suggest.records", count: group.hits.size), status(group.hits.first),
        actions.one? ? actions.first : nil)
    end

    # An opaque, stable key for keyboard focus and tests.
    def record_key(hit) = Digest::SHA256.hexdigest("#{hit.index}:#{hit.id}")[0, 16]
  end
end
