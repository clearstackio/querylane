# frozen_string_literal: true

module Querylane
  # Parsed query nodes. Ranges are character ranges into the query text.
  module Ast
    # `key:value`, or a bare word / quoted phrase when key is nil.
    Term = Data.define(:key, :value, :quoted, :range)
    # `-term`, `NOT term`, `-(…)`.
    Not = Data.define(:node, :range)
    # `a OR b OR c` (binds tighter than the implicit AND).
    Or = Data.define(:nodes, :range)
    # `( … )`, an AND of its nodes.
    Group = Data.define(:nodes, :range)
    # The whole query: an AND of its nodes.
    Root = Data.define(:nodes, :source)
  end
end
