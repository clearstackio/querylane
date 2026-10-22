# frozen_string_literal: true

# querylane — a Gmail-style search language, chips, facets and keyboard-driven
# results for Rails on Hotwire.
#
# Flow: Request (params) → Query (parse, interpret, validate) → Compiler
# (text + filters per index) → Searcher (backend) → Result (hits, chips,
# facets, state) → engine partials and Stimulus controllers.
require "rails"
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"
require "strscan"

require "querylane/version"
require "querylane/errors"
require "querylane/copy"
require "querylane/configuration"
require "querylane/filter"
require "querylane/scope"
require "querylane/context"
require "querylane/definition"
require "querylane/ast"
require "querylane/parser"
require "querylane/query"
require "querylane/compiler"
require "querylane/chips"
require "querylane/rewriter"
require "querylane/preview"
require "querylane/group_token"
require "querylane/suggest"
require "querylane/saving"
require "querylane/request"
require "querylane/result"
require "querylane/search"
require "querylane/searchers/meilisearch"
require "querylane/doctor"
require "querylane/presenter"
require "querylane/controller"
require "querylane/engine"

module Querylane
  class << self
    # @return [Querylane::Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Configures querylane once, at boot (an initializer in the host).
    #
    # @yieldparam config [Querylane::Configuration]
    def configure
      yield configuration
    end

    # Test hook.
    def reset_configuration!
      @configuration = nil
    end
  end
end
