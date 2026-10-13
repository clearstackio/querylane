# frozen_string_literal: true

module Querylane
  # Turns a valid Query into what a searcher runs: one text query (words and
  # the attributes to search) and a filter per index (without the scope).
  class Compiler
    # matching: :all (every word) or :frequency (relaxed; rare words kept).
    Compiled = Data.define(:text, :text_attributes, :filter_builder, :matching) do
      # @return [Querylane::Filter] the query's filter for one index
      def filter_for(index) = filter_builder.call(index.to_sym)
    end

    # @param query [Querylane::Query] valid
    # @return [Querylane::Compiler::Compiled]
    def self.compile(query)
      raise ArgumentError, "compile a valid query" unless query.valid?

      new(query).compile
    end

    def initialize(query)
      @query = query
      @definition = query.definition
    end

    def compile
      terms = @query.text_terms
      # Prefix matching is built in, so a "*" typed as a wildcard is dropped.
      text = terms.map { |term| term.quoted ? %("#{term.value}") : term.value.to_s.delete("*") }.compact_blank.join(" ").presence
      filter_nodes = @query.nodes.reject { |node| node.is_a?(Query::Term) && node.kind == :text }
      Compiled.new(text, @query.text_operator&.attributes, ->(index) { Filter.and(*filter_nodes.map { |node| to_filter(node, index) }) }, :all)
    end

    private

    def to_filter(node, index)
      case node
      when Query::Term then term_filter(node, index)
      when Ast::Not then Filter.not(to_filter(node.node, index))
      when Ast::Or then Filter.or(*node.nodes.map { |child| to_filter(child, index) })
      when Ast::Group then Filter.and(*node.nodes.map { |child| to_filter(child, index) })
      end
    end

    def term_filter(term, index)
      case term.kind
      when :filter then Filter.eq(term.operator.attribute, term.value)
      when :flag then @definition.flag_filter(term.operator, term.value, index: index)
      end
    end
  end
end
