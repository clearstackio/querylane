# frozen_string_literal: true

module Querylane
  # The meaning of a query: parsed, bare words interpreted, every term matched
  # to an operator of the definition and validated. One error at most.
  #
  #   query = Query.analyze(definition, "smith 5432 is:active")
  #   query.valid?  # => true
  #   query.nodes   # => [Term(:text name "smith"), Term(:filter last4 "5432"), Term(:flag is :active)]
  class Query
    # A resolved term. kind: :text, :filter or :flag.
    # raw: the token as typed (for "instead" readings of interpreted terms).
    Term = Data.define(:kind, :operator, :value, :quoted, :range, :interpreted, :raw)

    attr_reader :definition, :source, :nodes, :error

    # @param definition [Querylane::Definition]
    # @param source [String]
    # @return [Querylane::Query]
    def self.analyze(definition, source, config: Querylane.configuration)
      new(definition, source.to_s, config)
    end

    def valid? = error.nil?

    def blank? = source.strip.empty?

    # Top-level text terms (all share one operator).
    #
    # @return [Array<Term>]
    def text_terms = nodes.grep(Term).select { |term| term.kind == :text }

    # @return [Querylane::Definition::Text, nil]
    def text_operator = text_terms.first&.operator

    # Every term at any depth (inside NOT, OR and groups), in order.
    #
    # @return [Array<Term>]
    def terms = walk(nodes)

    # Whether every word is shorter than `length` and nothing else narrows the
    # search ("*" is not counted: legacy queries used it as a wildcard).
    def too_short?(length)
      return false if length.nil? || blank?

      terms.all? { |term| term.kind == :text } && terms.none? { |term| term.value.to_s.delete("*").length >= length }
    end

    # Terms whose operator is sensitive (member IDs, SSNs, last fours).
    #
    # @return [Array<Term>]
    def sensitive_terms = terms.select { |term| term.operator.respond_to?(:sensitive) && term.operator.sensitive }

    private

    def walk(nodes)
      nodes.flat_map do |node|
        case node
        when Term then [node]
        when Ast::Not then walk([node.node])
        when Ast::Or, Ast::Group then walk(node.nodes)
        else []
        end
      end
    end

    def initialize(definition, source, config)
      @definition = definition
      @source = source
      @nodes = []
      @error = nil
      root = Parser.parse(source, config: config)
      @nodes = root.nodes.map { |node| resolve(node, context: nil) }.freeze
      check_single_text_operator
    rescue Parser::Error => error
      @error = QueryError.new(error.message, error.range)
    rescue Invalid => invalid
      @error = invalid.error
      @nodes = [].freeze
    end

    class Invalid < StandardError
      attr_reader :error

      def initialize(message, range, fix = nil)
        super(message)
        @error = QueryError.new(message, range, fix)
      end
    end
    private_constant :Invalid

    def resolve(node, context:)
      case node
      when Ast::Term then resolve_term(node, context)
      when Ast::Not then Ast::Not.new(resolve(node.node, context: :not), node.range)
      when Ast::Or then Ast::Or.new(node.nodes.map { |child| resolve(child, context: :or) }, node.range)
      when Ast::Group then Ast::Group.new(node.nodes.map { |child| resolve(child, context: :group) }, node.range)
      end
    end

    def resolve_term(term, context)
      key, value, interpreted = term.key, term.value, false
      if key.nil? && !term.quoted && (reading = definition.interpret(value))
        key, value = reading
        interpreted = true
      end
      return text_term(definition.default_text, value, term, context, interpreted) if key.nil?

      raise Invalid.new(I18n.t("querylane.errors.parked", key: key, default: "%{key}: is not available yet."), term.range) if definition.parked.include?(key.to_s.downcase)

      operator = definition.operator(key) || raise(unknown_key(key, term))
      resolve_operator(operator, value, term, context, interpreted)
    end

    def resolve_operator(operator, value, term, context, interpreted)
      case operator
      when Definition::Text then text_term(operator, value, term, context, interpreted)
      when Definition::FilterOperator then filter_term(operator, value, term, interpreted)
      when Definition::Flags then flag_term(operator, value, term, interpreted)
      end
    end

    def text_term(operator, value, term, context, interpreted)
      if context
        message = {
          or: "OR joins operators, not names. Search one name at a time.",
          not: "- and NOT apply to operators, not names.",
          group: "Parentheses group operators, not names."
        }.fetch(context)
        raise Invalid.new(message, term.range)
      end
      Term.new(:text, operator, value, term.quoted, term.range, interpreted, term.value)
    end

    def filter_term(operator, value, term, interpreted)
      normalized = operator.normalize ? operator.normalize.call(value) : value
      if operator.format && !operator.format.match?(normalized)
        shown = operator.sensitive ? "That value" : "\"#{value}\""
        raise Invalid.new("#{shown} is not a valid #{operator.key}: value.", term.range)
      end
      Term.new(:filter, operator, normalized, term.quoted, term.range, interpreted, term.value)
    end

    def flag_term(operator, value, term, interpreted)
      symbol = value.to_s.downcase.to_sym
      unless operator.values.key?(symbol)
        raise Invalid.new("#{value} is not a value of #{operator.key}:. Try #{operator.values.keys.join(", ")}.", term.range)
      end
      Term.new(:flag, operator, symbol, term.quoted, term.range, interpreted, term.value)
    end

    def check_single_text_operator
      operators = text_terms.map(&:operator).uniq
      return if operators.size <= 1

      second = text_terms.find { |term| term.operator == operators.last }
      others = definition.filters.map { |filter| "#{filter.key}:" }.first(2).join(" or ")
      raise Invalid.new("Search #{operators.map(&:key).join(" or ")} one at a time, or combine with #{others}.", second.range)
    end

    # "stauts: is not an operator. Did you mean status:?", with the corrected term as the fix.
    def unknown_key(key, term)
      suggestion = definition.operator_keys.min_by { |candidate| distance(candidate, key) }
      return Invalid.new("#{key}: is not an operator.", term.range) unless suggestion && distance(suggestion, key) <= 2

      fixed = source[term.range].sub(/\A[^:]+/, suggestion)
      Invalid.new("#{key}: is not an operator. Did you mean #{suggestion}:?", term.range, fixed)
    end

    # Levenshtein distance (short strings only).
    def distance(a, b)
      previous = (0..b.length).to_a
      a.each_char.with_index(1) do |char_a, i|
        current = [i]
        b.each_char.with_index(1) do |char_b, j|
          current << [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + ((char_a == char_b) ? 0 : 1)].min
        end
        previous = current
      end
      previous.last
    end
  end
end
