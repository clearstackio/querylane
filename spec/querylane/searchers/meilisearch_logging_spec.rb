# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "meilisearch"

# An unavailable search must say why in the host's log, without the
# Meilisearch message: it can echo the filter, and filters carry member data.
RSpec.describe Querylane::Searchers::Meilisearch do
  let(:log) { StringIO.new }

  before { Querylane.configure { |config| config.logger = Logger.new(log) } }

  def counts_with(error)
    client = Object.new
    client.define_singleton_method(:multi_search) { |**| raise error }
    described_class.new(client: client).group_counts(definition: TestSearch::DEFINITION,
      scope: Querylane::Scope.unrestricted(:employees, :ebmr), attribute: :policy_number, values: %w[123456])
  end

  it "logs the code, type and status of an API error, but not its message" do
    error = Meilisearch::ApiError.new(400, "Bad Request",
      {"code" => "invalid_search_filter", "type" => "invalid_request", "message" => "filter `ssn = 123456789` is invalid"})

    expect { counts_with(error) }.to raise_error(Querylane::SearchUnavailable, "Meilisearch ApiError invalid_search_filter")
    expect(log.string).to include("[querylane] search unavailable: Meilisearch ApiError code=invalid_search_filter type=invalid_request http=400")
    expect(log.string).not_to include("123456789")
  end

  it "logs why a connection failed" do
    error = Meilisearch::CommunicationError.new("Failed to open TCP connection to search:7700 (Connection refused)")

    expect { counts_with(error) }.to raise_error(Querylane::SearchUnavailable, "Meilisearch CommunicationError")
    expect(log.string).to include("search unavailable: Meilisearch CommunicationError", "Connection refused")
  end

  it "drops credentials and the query string from a quoted URL" do
    error = Meilisearch::CommunicationError.new("bad URI(is not URI?): http://admin:secret@search:7700/multi-search?token=abc")

    expect { counts_with(error) }.to raise_error(Querylane::SearchUnavailable)
    expect(log.string).to include("http://search:7700/multi-search")
    expect(log.string).not_to include("secret", "token=abc")
  end

  it "has a logger of its own when the host sets none" do
    Querylane.reset_configuration!

    expect(Querylane.configuration.logger).to respond_to(:warn)
  end
end
