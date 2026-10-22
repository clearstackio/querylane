# frozen_string_literal: true

module Querylane
  # Turns query text into an Ast::Root (syntax only; meaning is Query's job).
  #
  # Grammar (Gmail style: implicit AND, OR binds tighter):
  #   query := unit*            unit := unary ("OR" unary)*
  #   unary := ("-" | "NOT") atom | atom
  #   atom  := "(" query ")" | key ":" value | word | "phrase"
  #
  # Bounded: length, nesting depth and number of terms (Configuration).
  class Parser
    # A syntax error with the character range it concerns.
    class Error < StandardError
      attr_reader :range

      def initialize(message, range)
        super(message)
        @range = range
      end
    end

    Token = Data.define(:type, :range, :key, :value, :quoted)

    KEY = /([A-Za-z][A-Za-z0-9_]*):/
    QUOTED = /"((?:[^"\\]|\\.)*)"/
    BARE = /[^\s()"]+/

    # @param source [String]
    # @return [Querylane::Ast::Root]
    # @raise [Querylane::Parser::Error]
    def self.parse(source, config: Querylane.configuration)
      new(source.to_s, config).parse
    end

    def initialize(source, config)
      @source = source
      @config = config
    end

    def parse
      if @source.length > @config.max_length
        raise Error.new(message(:too_long, max: @config.max_length), 0...@source.length)
      end

      @tokens = tokenize
      @position = 0
      @depth = 0
      @terms = 0
      nodes = parse_sequence(closing: false)
      Ast::Root.new(nodes.freeze, @source)
    end

    private

    def tokenize
      scanner = StringScanner.new(@source)
      tokens = []
      until scanner.eos?
        next if scanner.skip(/\s+/)

        start = scanner.charpos
        tokens << next_token(scanner, start)
      end
      tokens
    end

    def next_token(scanner, start)
      if scanner.scan("(") then token(:lparen, scanner, start)
      elsif scanner.scan(")") then token(:rparen, scanner, start)
      elsif scanner.scan(/OR(?=[\s()]|\z)/) then token(:or, scanner, start)
      elsif scanner.scan(/NOT(?=\s)/) then token(:not, scanner, start)
      elsif scanner.scan(/-(?=[^\s)])/) then token(:minus, scanner, start)
      elsif scanner.scan(KEY) then key_token(scanner, start, scanner[1])
      elsif scanner.scan(QUOTED) then token(:term, scanner, start, value: unescape(scanner[1]), quoted: true)
      elsif scanner.scan('"') then raise Error.new(message(:close_quote), start...@source.length)
      else
        scanner.scan(BARE)
        token(:term, scanner, start, value: scanner.matched)
      end
    end

    def key_token(scanner, start, key)
      if scanner.scan(QUOTED)
        token(:term, scanner, start, key: key, value: unescape(scanner[1]), quoted: true)
      elsif scanner.scan(BARE)
        token(:term, scanner, start, key: key, value: scanner.matched)
      else
        raise Error.new(message(:needs_value, key: key), start...scanner.charpos)
      end
    end

    def token(type, scanner, start, key: nil, value: nil, quoted: false)
      Token.new(type, start...scanner.charpos, key, value, quoted)
    end

    def unescape(text) = text.gsub(/\\(.)/, '\1')

    def parse_sequence(closing:)
      nodes = []
      until done? || (closing && peek?(:rparen))
        raise Error.new(message(:unexpected, text: ")"), current.range) if peek?(:rparen)

        nodes << parse_or
      end
      nodes
    end

    def parse_or
      parts = [parse_unary]
      while peek?(:or)
        operator = advance
        raise Error.new(message(:or_needs_terms), operator.range) if done? || peek?(:rparen) || peek?(:or)

        parts << parse_unary
      end
      return parts.first if parts.one?

      Ast::Or.new(parts.freeze, parts.first.range.begin...parts.last.range.end)
    end

    def parse_unary
      if peek?(:minus) || peek?(:not)
        operator = advance
        raise Error.new(message(:needs_term, operator: (operator.type == :not) ? "NOT" : "-"), operator.range) if done?

        node = parse_atom
        return Ast::Not.new(node, operator.range.begin...node.range.end)
      end
      parse_atom
    end

    def parse_atom
      raise Error.new(message(:ended_early), @source.length...@source.length) if done?

      case current.type
      when :lparen then parse_group
      when :or then raise Error.new(message(:or_needs_terms), current.range)
      when :term then parse_term
      else raise Error.new(message(:unexpected, text: @source[current.range]), current.range)
      end
    end

    def parse_group
      open = advance
      @depth += 1
      raise Error.new(message(:too_deep, max: @config.max_depth), open.range) if @depth > @config.max_depth

      nodes = parse_sequence(closing: true)
      raise Error.new(message(:close_parenthesis), open.range.begin...@source.length) unless peek?(:rparen)
      raise Error.new(message(:empty_parentheses), open.range) if nodes.empty?

      close = advance
      @depth -= 1
      Ast::Group.new(nodes.freeze, open.range.begin...close.range.end)
    end

    def parse_term
      term = advance
      @terms += 1
      raise Error.new(message(:too_many_terms, max: @config.max_terms), term.range) if @terms > @config.max_terms

      Ast::Term.new(term.key&.downcase, term.value, term.quoted, term.range)
    end

    # Syntax errors share Query's localized messages (`querylane.errors.*`).
    def message(name, **values) = Query.message(name, **values)

    def current = @tokens[@position]

    def advance
      token = current
      @position += 1
      token
    end

    def peek?(type) = !done? && current.type == type

    def done? = @position >= @tokens.length
  end
end
