# frozen_string_literal: true

module Querylane
  # "Searching for" chips: one per top-level term of a valid query (all name
  # words share one chip). Sensitive values are masked; nothing here repeats a
  # sensitive value in clear.
  module Chips
    # alternatives: other readings of an interpreted term ("Division 5432 instead");
    # words: the chip of the query's words (names), not a filter.
    Chip = Data.define(:index, :label, :ranges, :alternatives, :words) do
      def initialize(index:, label:, ranges:, alternatives: [], words: false)
        super
      end
    end
    Alternative = Data.define(:index, :label, :text)

    module_function

    # @param query [Querylane::Query]
    # @return [Array<Chip>]
    def for(query)
      return [] unless query.valid?

      chips = []
      if (texts = query.text_terms).any?
        words = texts.map { |term| term.quoted ? %("#{term.value}") : term.value }.join(" ")
        chips << [format(texts.first.operator, mask(words, texts.first.operator.mask)), texts.map(&:range), [], true]
      end
      query.nodes.each do |node|
        next if node.is_a?(Query::Term) && node.kind == :text

        chips << [label(node), [node.range], alternatives(query, node)]
      end
      chips.each_with_index.map do |(text, ranges, others, words), index|
        Chip.new(index: index, label: text, ranges: ranges, alternatives: others || [], words: words || false)
      end
    end

    # Other readings of an interpreted term, each with the explicit text it
    # would become (e.g. "div:5432").
    def alternatives(query, node)
      return [] unless node.is_a?(Query::Term) && node.interpreted

      query.definition.alternatives(node.raw).each_with_index.filter_map do |(key, value), index|
        operator = query.definition.operator(key)
        next unless operator

        reading = Query.analyze(query.definition, "#{key}:#{value}")
        next unless reading.valid?

        Alternative.new(index, "#{label(reading.nodes.first)} instead", "#{operator.key}:#{value}")
      end
    end

    def label(node)
      case node
      when Query::Term then term_label(node)
      when Ast::Not then "Not #{label(node.node)}"
      when Ast::Or then node.nodes.map { |child| label(child) }.join(" or ")
      when Ast::Group then "(#{node.nodes.map { |child| label(child) }.join(" and ")})"
      end
    end

    def term_label(term)
      case term.kind
      when :filter then format(term.operator, mask(term.value, term.operator.mask))
      when :flag then "#{term.operator.label} #{term.operator.values.fetch(term.value)}"
      when :text then format(term.operator, term.value)
      end
    end

    def format(operator, value) = operator.label.gsub("%{value}", value.to_s)

    # @param value [String]
    # @param mask [Symbol] :none, :all, :last4, :count
    def mask(value, mask)
      case mask
      when :none then value
      when :last4 then (value.length >= 4) ? "•••-••-#{value[-4..]}" : "•" * value.length
      when :count then I18n.t("querylane.chips.count", count: value.length, default: "%{count} characters")
      else "•" * value.length
      end
    end
  end
end
