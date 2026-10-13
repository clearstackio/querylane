# frozen_string_literal: true

module Querylane
  # Saved searches: what may be saved, and the host's store.
  #
  # A query holding a sensitive term (typed or worked out by the interpreter,
  # e.g. "5432" read as a last four), or any value the interpreter would read
  # as one (a quoted "123456789", name:123456789), is never saved; the refusal
  # offers the query without it.
  #
  # The store is the host's (`d.saved store: "SavedSearchStore"`): an object
  # or class name responding to
  #   all(context:)                → [#id, #name, #query, #used_at]
  #   create(context:, name:, query:)
  #   use(context:, id:)           → the saved search (and records its use), or nil
  module Saving
    # value: the sensitive text as shown (masked by its operator's mask);
    # operator: what it was read as; rest: the query without sensitive terms.
    Refusal = Data.define(:value, :operator, :rest)

    module_function

    # @param query [Querylane::Query] valid
    # @return [Refusal, nil] nil when the query may be saved
    def refusal(query)
      definition = query.definition
      sensitive = query.terms.filter_map do |term|
        # A word (a name, quoted or name:) could hide an ID the box would read
        # as sensitive; a value already given to a filter (div:0001) cannot.
        operator = sensitive?(term.operator) ? term.operator : (term.kind == :text && reading(definition, term.value))
        [term, operator] if operator
      end
      return if sensitive.empty?

      term, operator = sensitive.first
      value = Chips.mask(term.value.to_s, (operator.respond_to?(:mask) && operator.mask != :count) ? operator.mask : :all)
      Refusal.new(value, Suggest.hint(operator), Rewriter.remove(query.source, sensitive.map { |found, _| found.range }))
    end

    def sensitive?(operator) = operator.respond_to?(:sensitive) && operator.sensitive

    # The sensitive operator the interpreter would read this value as, if any.
    def reading(definition, value)
      key, = definition.interpret(value.to_s)
      operator = key && definition.operator(key)
      operator if sensitive?(operator)
    end
  end
end
