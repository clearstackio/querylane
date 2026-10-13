# frozen_string_literal: true

module Querylane
  # What the current user may search: the logical indexes and a permission
  # filter for each. The host builds it on the server (never from params);
  # every hit, count and facet query ANDs the index's permission filter.
  #
  #   Querylane::Scope.new(employees: Querylane::Filter.in(:policy_company_id, %w[SI YI]))
  class Scope
    # A scope with no permission filter. Must be chosen deliberately.
    #
    # @param indexes [Array<Symbol>]
    def self.unrestricted(*indexes)
      new(indexes.flatten.to_h { |index| [index, Filter.everything] })
    end

    # The user's access could not be checked: nothing is searched and the
    # page says so (never an unrestricted or stale answer).
    def self.denied = Denied.new

    # @param filters_by_index [Hash{Symbol => Querylane::Filter}]
    def initialize(filters_by_index = {})
      raise MissingScopeError, "A scope needs at least one index" if filters_by_index.blank?

      @filters = filters_by_index.to_h { |index, filter| [index.to_sym, filter || raise(MissingScopeError, "No permission filter for #{index}")] }.freeze
    end

    def denied? = false

    # @return [Array<Symbol>]
    def indexes = @filters.keys

    # @return [Querylane::Filter]
    def filter_for(index) = @filters.fetch(index.to_sym)

    # This scope narrowed by extra filters per index (query-filter hooks).
    #
    # @param extra [Hash{Symbol => Querylane::Filter}]
    # @return [Querylane::Scope]
    def narrowed(extra)
      Scope.new(@filters.to_h { |index, filter| [index, Filter.and(filter, extra.fetch(index, Filter.everything))] })
    end

    # See Scope.denied.
    class Denied < Scope
      def initialize
        @filters = {}.freeze
      end

      def denied? = true
    end
  end
end
