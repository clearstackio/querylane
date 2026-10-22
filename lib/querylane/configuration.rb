# frozen_string_literal: true

module Querylane
  # Process-wide settings, set once in a host initializer:
  #
  #   Querylane.configure do |config|
  #     config.searcher = -> { Querylane::Searchers::Meilisearch.new(client: MeilisearchService.client) }
  #     config.logger = Rails.logger
  #   end
  class Configuration
    # Name of the query parameter (filtered from logs by the engine).
    attr_accessor :param_name
    # Bounds every query is checked against.
    attr_accessor :max_length, :max_depth, :max_terms
    # Debounce (ms) before a typed query is submitted.
    attr_accessor :debounce_ms
    # Allows GET requests to carry the query (off: POST only).
    attr_accessor :allow_get_query

    attr_writer :searcher

    # Where querylane writes why a search could not run. A host passes its
    # own (Rails.logger); without one querylane logs to standard output.
    attr_writer :logger

    # How long a group token ("more records", preview) stays valid.
    attr_accessor :group_token_ttl

    # Records read for suggestions (header box and palette), and people shown.
    attr_accessor :suggest_records, :suggest_people

    def initialize
      @group_token_ttl = 3600
      @suggest_records = 20
      @suggest_people = 5
      @param_name = :search_query
      @max_length = 256
      @max_depth = 3
      @max_terms = 20
      @debounce_ms = 300
      @allow_get_query = false
      @searcher = nil
      @logger = ActiveSupport::Logger.new($stdout)
    end

    # @return [Logger]
    attr_reader :logger

    # The searcher for this request. A callable is resolved on every call, so
    # it can follow code reloading and per-request clients.
    #
    # @return [#search]
    def searcher
      found = @searcher.respond_to?(:call) ? @searcher.call : @searcher
      found || raise(ConfigurationError, "Set Querylane.configure { |c| c.searcher = ... }")
    end
  end
end
