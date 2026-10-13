# frozen_string_literal: true

module Querylane
  # What the options panel would write: the composed query and the parts kept
  # as typed, with sensitive values masked for display. Built without a search.
  #
  # text, kept: masked display strings (nil when the box query is invalid);
  # error: a QueryError for the composed text, or the box's own error.
  Preview = Data.define(:text, :kept, :error) do
    # @param definition [Querylane::Definition]
    # @param source [String] the box text
    # @param fields [Hash] compose fields from the panel
    # @return [Querylane::Preview]
    def self.for(definition, source, fields, config: Querylane.configuration)
      query = Query.analyze(definition, source.to_s, config: config)
      return new(nil, nil, query.error) unless query.valid?

      composed = Query.analyze(definition, Rewriter.compose(query, fields.to_h.transform_keys(&:to_s)), config: config)
      kept = Query.analyze(definition, Rewriter.panel(query).kept, config: config)
      new(masked(composed), masked(kept), composed.error)
    end

    # The query text with every sensitive term's value masked.
    #
    # @param query [Querylane::Query]
    # @return [String]
    def self.masked(query)
      text = query.source.dup
      query.terms.select { |term| mask_of(term.operator) != :none }.sort_by { |term| -term.range.begin }.each do |term|
        segment = text[term.range]
        value = segment.split(":", 2).last
        text[term.range] = segment.delete_suffix(value) + Chips.mask(value.delete('"'), mask_of(term.operator))
      end
      text
    end

    def self.mask_of(operator)
      # :count reads as prose ("9 characters"); inside query text use dots.
      return :none unless operator.respond_to?(:mask)

      (operator.mask == :count) ? :all : operator.mask
    end
    private_class_method :mask_of
  end
end
