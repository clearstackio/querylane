# frozen_string_literal: true

module Querylane
  # Suggestions for the last word of a query (header box and palette):
  # operator names it starts ("pol" → policy:) and flag values after a key
  # ("is:" → is:active). The rest of the text is what people are searched by.
  module Suggest
    # word: replaces the query's last word (the page never repeats the query).
    Completion = Data.define(:word, :hint)

    module_function

    # @param definition [Querylane::Definition]
    # @param text [String] the box text
    # @return [Array<Completion>]
    def completions(definition, text)
      word = split(text).last
      return [] if word.empty? || word.start_with?("-", "(", '"')

      key, partial = word.split(":", 2)
      partial.nil? ? operator_completions(definition, word) : value_completions(definition, key, partial)
    end

    # The text people are searched by: without a trailing word that is being
    # completed into an operator (it is not a name).
    #
    # @return [String]
    def people_text(definition, text)
      head, word = split(text)
      (completions(definition, text).any? || word.include?(":")) ? head.rstrip : text
    end

    def split(text)
      text = text.to_s
      word = text[/\S*\z/]
      [text[0, text.length - word.length], word]
    end

    def operator_completions(definition, word)
      return [] if word.length < 2

      typed = word.downcase
      (definition.texts + definition.filters + definition.flags).filter_map do |operator|
        keys = [operator.key, *(operator.respond_to?(:aliases) ? operator.aliases : [])].map(&:to_s)
        next if keys.include?(typed)

        key = keys.find { |candidate| candidate.start_with?(typed) }
        Completion.new("#{key}:", hint(operator)) if key
      end
    end

    def value_completions(definition, key, partial)
      flags = definition.operator(key)
      return [] unless flags.is_a?(Definition::Flags)

      flags.values.select { |value, _| value.to_s.start_with?(partial.downcase) && value.to_s != partial.downcase }
        .map { |value, label| Completion.new("#{key}:#{value}", label) }
    end

    # @return [String] a short description of an operator
    def hint(operator)
      return operator.label if operator.is_a?(Definition::Flags)

      operator.label.gsub("%{value}", "").strip
    end
  end
end
