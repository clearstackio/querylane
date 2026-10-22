# frozen_string_literal: true

module Querylane
  # Host-supplied copy that may be a locale key or plain text: a panel row's
  # `hint:` and `placeholder:`, a filter's `invalid:` sentence. Resolved when
  # shown (never when the definition is built), so a memoized definition still
  # follows the current locale.
  #
  #   Copy.text(:"search.hints.name")        # => I18n.t("search.hints.name")
  #   Copy.text("search.hints.name")         # => the same (a dotted key)
  #   Copy.text("Exact last name, any case") # => as given
  module Copy
    # A dotted locale key: no spaces, at least one dot between word parts.
    KEY = /\A[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+\z/

    module_function

    # @param value [String, Symbol, nil] a locale key or text
    # @return [String, nil] the translation for a key, the text otherwise
    def text(value)
      case value
      when nil then nil
      when Symbol then I18n.t(value)
      else value.to_s.match?(KEY) ? I18n.t(value.to_s) : value.to_s
      end
    end
  end
end
