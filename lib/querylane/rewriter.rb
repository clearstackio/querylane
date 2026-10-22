# frozen_string_literal: true

module Querylane
  # Edits query text structurally, so facets and chips never disagree with
  # the box: the query text is the only search state.
  #
  # A facet value is "ticked" when the query has, at top level, a positive term
  # for it (`is:active`) or an OR group made only of positive terms of the same
  # operator containing it (`(policy:1 OR policy:2)`). Toggling removes every
  # canonical occurrence of the facet and appends one canonical expression with
  # the new value set.
  module Rewriter
    module_function

    # @param query [Querylane::Query] valid
    # @param facet [Querylane::Definition::Facet]
    # @return [Array<String>] ticked values, in order of appearance
    def ticked(query, facet)
      occurrences(query, facet).flat_map(&:last).uniq
    end

    # @return [String] the query text with the value ticked or unticked
    def toggle(query, facet, value)
      value = canonical_value(query.definition, facet, value)
      return query.source if value.nil?

      current = ticked(query, facet)
      values = current.include?(value) ? current - [value] : current + [value]
      text = remove(query.source, occurrences(query, facet).map(&:first))
      [text, expression(query.definition, facet, values)].reject(&:empty?).join(" ")
    end

    # The query without this facet's canonical terms (the facet's counting base).
    #
    # @return [String]
    def without(query, facet)
      remove(query.source, occurrences(query, facet).map(&:first))
    end

    # @param ranges [Array<Range>]
    # @return [String] the text with the ranges removed; whitespace is tidied
    #   only where a range was cut, so quoted values stay exactly as typed
    def remove(source, ranges)
      text = source.dup
      ranges.sort_by(&:begin).reverse_each do |range|
        before = text[0...range.begin].rstrip
        after = text[range.end..].to_s.lstrip
        text = [before, after].reject(&:empty?).join(" ")
      end
      text.strip
    end

    # The query with one filter chip's term replaced by its typed value as
    # plain words ("smith last:smiht" → "smith smiht"), for a chip that offers
    # it (Chip#as_words); otherwise the query unchanged.
    #
    # @param query [Querylane::Query] valid
    # @param chip [Querylane::Chips::Chip, nil]
    # @return [String]
    def as_words(query, chip)
      return query.source unless chip&.as_words

      words_in_place(query, chip.ranges.first, chip.as_words)
    end

    # The query text with `range` replaced by `typed` as plain words.
    #
    # @return [String]
    def words_in_place(query, range, typed)
      words = typed.split.map { |word| bare_word(query.definition, word) }.join(" ")
      # Keep the words apart from a neighbour typed without a space (`last:"x"is:active`).
      before = (range.begin.positive? && !query.source[range.begin - 1].match?(/\s/)) ? " " : ""
      after = (range.end < query.source.length && !query.source[range.end].match?(/\s/)) ? " " : ""
      replace(query.source, range, "#{before}#{words}#{after}")
    end

    # A word that reads back as a plain word: anything the parser would take
    # as syntax (an operator key, a leading "-", OR, NOT, brackets, quotes) or
    # the interpreter would read as an operator ("1234" as a last four) is
    # quoted, since quoted words are never interpreted.
    def bare_word(definition, word)
      plain = word.match?(/\A[^\s()"-][^\s()"]*\z/) && !word.match?(/\A#{Parser::KEY}/o) && !%w[OR NOT].include?(word) &&
        definition.interpret(word).nil?
      plain ? word : quoted(word)
    end

    # The options panel's view of a query: each field's value (keyed by the
    # compose field name), the parts no field can show (kept as typed), and,
    # per masked field, the masked terms it leaves in the box (masked values
    # never become field values, so they never reach HTML).
    Panel = Data.define(:values, :kept, :held)
    # One word of a field, and whether the user quoted it.
    Token = Data.define(:text, :quoted)

    # @param query [Querylane::Query] valid
    # @return [Panel]
    def panel(query)
      definition = query.definition
      used = []
      values = {"options" => []}
      held = {}
      # Options first: their exact text (e.g. "-is:terminated") is not a flag value.
      definition.panel_rows.sort_by { |row| (row.kind == :options) ? 0 : 1 }.each do |row|
        case row.kind
        when :options
          row.keys.each do |key|
            node = query.nodes.find { |candidate| !used.include?(candidate.range) && query.source[candidate.range] == definition.option(key).text }
            next unless node

            used << node.range
            values["options"] << key.to_s
          end
        when :flags
          found = occurrences_of(query, definition.operator(row.keys.first), values: row.values).reject { |pair| used.include?(pair.first) }
          used.concat(found.map(&:first))
          values[row.name] = found.flat_map(&:last)
        else
          row.keys.group_by { |key| row.bare ? row.name : key.to_s }.each do |name, keys|
            found = keys.flat_map { |key| field_terms(query, definition.operator(key)) }.sort_by { |range, _| range.begin }
            values[name] = ""
            if row.masked
              held[name] = found.map { |range, _| Preview.masked(Query.analyze(definition, query.source[range])) }.join(" ").presence
            else
              used.concat(found.map(&:first))
              values[name] = found.flat_map(&:last).join(" ")
            end
          end
        end
      end
      Panel.new(values, remove(query.source, used), held.compact)
    end

    # Rebuilds the query from options-panel fields: the parts the panel cannot
    # show stay as typed, then each field writes its canonical text.
    #
    # @param fields [Hash{String => String, Array<String>}] compose field name → value
    # @return [String]
    def compose(query, fields)
      definition = query.definition
      parts = [panel(query).kept]
      definition.panel_rows.each do |row|
        case row.kind
        when :options
          chosen = Array(fields["options"]).map(&:to_s)
          row.keys.each { |key| parts << definition.option(key).text if chosen.include?(key.to_s) }
        when :flags
          flag = definition.operator(row.keys.first)
          parts << group(flag.key, Array(fields[row.name]).map(&:to_s) & definition.flag_values(flag, row.values).keys.map(&:to_s))
        else
          if row.bare
            parts << tokens(fields[row.name]).map { |token| token.quoted ? quoted(token.text) : token.text }.join(" ")
          else
            row.keys.each { |key| parts << write(definition.operator(key), fields[key.to_s]) }
          end
        end
      end
      parts.reject(&:empty?).join(" ")
    end

    # Field text → tokens: "quoted phrases" (with \" and \\ escapes) stay one
    # token and remember their quotes; everything else splits on spaces.
    def tokens(value)
      value.to_s.scan(/"((?:[^"\\]|\\.)*)"|(\S+)/).filter_map do |phrase, word|
        phrase ? Token.new(phrase.gsub(/\\(.)/, '\1'), true) : Token.new(word, false)
      end.reject { |token| token.text.empty? }
    end

    # One input's value as query text for its operator; quoted tokens stay quoted.
    def write(operator, value)
      found = tokens(value)
      case operator
      when Definition::Text
        written = found.map { |token| token.quoted ? quoted(token.text) : quote(token.text) }
        operator.default ? written.join(" ") : written.map { |text| "#{operator.key}:#{text}" }.join(" ")
      else
        found = found.map { |token| (operator.normalize && !typed?(operator)) ? token.with(text: operator.normalize.call(token.text)) : token }
        join_or(found.uniq.map { |token| "#{operator.key}:#{token.quoted ? quoted(token.text) : quote(token.text)}" })
      end
    end

    def group(key, values)
      join_or(values.uniq.map { |value| "#{key}:#{quote(value)}" })
    end

    def join_or(terms)
      (terms.size > 1) ? "(#{terms.join(" OR ")})" : terms.first.to_s
    end

    # Ranges and display values (quoted as typed) of an operator's top-level
    # terms: words for a text operator; terms or OR groups for a filter.
    def field_terms(query, operator)
      if operator.is_a?(Definition::Text)
        query.text_terms.select { |term| term.operator.equal?(operator) }.map { |term| [term.range, [display(term)]] }
      else
        query.nodes.filter_map do |outer|
          node = unwrap(outer)
          if term_of?(node, operator)
            [outer.range, [display(node)]]
          elsif node.is_a?(Ast::Or) && node.nodes.all? { |child| term_of?(child, operator) }
            [outer.range, node.nodes.map { |child| display(child) }]
          end
        end
      end
    end

    # A field's text for a term: quoted as typed; a `display_value: :typed` filter
    # shows the value as typed, others (and interpreted terms, whose typed
    # token would read differently once prefixed) the normalized value.
    def display(term)
      value = (typed?(term.operator) && !term.interpreted) ? term.raw.to_s : term.value.to_s
      term.quoted ? quoted(value) : value
    end

    def typed?(operator) = operator.is_a?(Definition::FilterOperator) && operator.display_value == :typed

    # Always quoted, with " and \ escaped.
    def quoted(value) = %("#{value.to_s.gsub(/["\\]/) { |char| "\\#{char}" }}")

    # Top-level terms of an operator, alone or as an OR group of that operator
    # only; with `values`, only those whose every value is in the list.
    def occurrences_of(query, operator, values: nil)
      allowed = values&.map(&:to_s)
      found = occurrences_of_any(query, operator)
      allowed ? found.select { |_range, found_values| (found_values - allowed).empty? } : found
    end

    def occurrences_of_any(query, operator)
      query.nodes.filter_map do |outer|
        node = unwrap(outer)
        if term_of?(node, operator)
          [outer.range, [node.value.to_s]]
        elsif node.is_a?(Ast::Or) && node.nodes.all? { |child| term_of?(child, operator) }
          [outer.range, node.nodes.map { |child| child.value.to_s }]
        end
      end
    end

    # @return [String] the text with one range replaced
    def replace(source, range, text)
      [source[0...range.begin], text, source[range.end..]].join
    end

    # A toggle value in the form the query would hold, or nil if invalid.
    def canonical_value(definition, facet, value)
      operator = operator_for(definition, facet)
      case operator
      when Definition::Flags
        symbol = value.to_s.downcase.to_sym
        definition.flag_values(operator, facet.values).key?(symbol) ? symbol.to_s : nil
      when Definition::FilterOperator
        normalized = operator.normalize ? operator.normalize.call(value.to_s) : value.to_s
        (operator.format.nil? || operator.format.match?(normalized)) ? normalized : nil
      end
    end

    # @return [Array<Array(Range, Array<String>)>]
    def occurrences(query, facet)
      return [] unless query.valid?

      occurrences_of(query, operator_for(query.definition, facet), values: facet.values)
    end

    def expression(definition, facet, values)
      operator = operator_for(definition, facet)
      terms = values.map { |value| "#{operator.key}:#{quote(value)}" }
      (terms.size > 1) ? "(#{terms.join(" OR ")})" : terms.first.to_s
    end

    def operator_for(definition, facet)
      key = facet.flag || facet.filter
      definition.operator(key)
    end

    # `(a OR b)` parses as a group holding one OR node; look through it.
    def unwrap(node)
      (node.is_a?(Ast::Group) && node.nodes.one?) ? unwrap(node.nodes.first) : node
    end

    def term_of?(node, operator)
      node.is_a?(Query::Term) && node.operator.equal?(operator)
    end

    def quote(value)
      value.to_s.match?(/\A[^\s()"]+\z/) ? value.to_s : quoted(value)
    end
  end
end
