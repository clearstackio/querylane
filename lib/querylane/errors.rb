# frozen_string_literal: true

module Querylane
  class Error < StandardError; end

  # The host wired querylane incorrectly (raised at boot or first use).
  class ConfigurationError < Error; end

  # A search was attempted without a server-built Scope.
  class MissingScopeError < Error; end

  # The backend could not answer (timeout, unavailable, bad response).
  class SearchUnavailable < Error; end

  # A host hook raised or returned something it may not. The search is
  # aborted; results are never shown without the hook's filtering.
  class HookError < Error; end

  # A problem with what the user typed. The message is safe to show (it never
  # repeats a sensitive value); the range points into the query text.
  # fix: text that would replace `range` to correct the query (did-you-mean), or nil.
  QueryError = Data.define(:message, :range, :fix) do
    def initialize(message:, range:, fix: nil)
      super
    end
  end
end
