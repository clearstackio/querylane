# frozen_string_literal: true

module Querylane
  # Backend-neutral filter tree. Hosts build filters with these constructors;
  # a searcher renders them (Meilisearch: Searchers::Meilisearch::Expression).
  #
  #   Filter.and(Filter.eq(:status, "A"), Filter.not(Filter.eq(:category, "MNLC")))
  module Filter
    Eq = Data.define(:attribute, :value)
    In = Data.define(:attribute, :values)
    Null = Data.define(:attribute)
    Missing = Data.define(:attribute)
    And = Data.define(:filters)
    Or = Data.define(:filters)
    Not = Data.define(:filter)
    # A backend expression written by the host (e.g. an existing permission
    # filter string). Rendered as-is; never built from user input.
    Raw = Data.define(:expression)
    Everything = Data.define
    Nothing = Data.define

    module_function

    def eq(attribute, value) = Eq.new(attribute.to_s, value)

    def in(attribute, values) = In.new(attribute.to_s, Array(values))

    # The attribute is present with a null value.
    def null(attribute) = Null.new(attribute.to_s)

    # The attribute is absent from the document.
    def missing(attribute) = Missing.new(attribute.to_s)

    # AND of the filters. No filters (or only Everything) matches everything;
    # any Nothing matches nothing.
    def and(*filters)
      filters = filters.flatten.compact
      return Nothing.new if filters.any?(Nothing)

      filters = filters.reject { |filter| filter.is_a?(Everything) }
      return Everything.new if filters.empty?

      filters.one? ? filters.first : And.new(filters)
    end

    # OR of the filters. No filters (or only Nothing) matches nothing — so an
    # empty list of grants never widens a scope; any Everything matches everything.
    def or(*filters)
      filters = filters.flatten.compact
      return Everything.new if filters.any?(Everything)

      filters = filters.reject { |filter| filter.is_a?(Nothing) }
      return Nothing.new if filters.empty?

      filters.one? ? filters.first : Or.new(filters)
    end

    def not(filter)
      case filter
      when Everything then Nothing.new
      when Nothing then Everything.new
      else Not.new(filter)
      end
    end

    # Matches every document (an unrestricted scope).
    def everything = Everything.new

    # Matches no document (e.g. a user with no grants).
    def nothing = Nothing.new

    # @param expression [String] a backend filter written by the host
    def raw(expression) = Raw.new(expression.to_s)
  end
end
