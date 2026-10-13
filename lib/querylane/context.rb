# frozen_string_literal: true

module Querylane
  # Per-request facts hooks may use (the current user, the request, anything
  # the host adds). Built by the host controller; never from params.
  Context = Data.define(:user, :request, :extras) do
    def initialize(user: nil, request: nil, extras: {})
      super
    end
  end
end
