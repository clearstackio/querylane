# frozen_string_literal: true

module Querylane
  # What a search understands: indexes, operators, facets, sorts and paging.
  # Built once with a block and frozen; host classes are referenced by name and
  # resolved per call, so Rails code reloading never leaves stale methods.
  #
  #   MEMBERS = Querylane::Definition.build(:members) do |d|
  #     d.index  :employees, name: -> { "employees_#{Rails.env}" }
  #     d.text   :name, attributes: %i[full_name], default: true, label: "Name contains %{value}"
  #     d.filter :policy, attribute: :policy_number, label: "Policy %{value}"
  #     d.flags  :is, alias: :status, attribute: :status_label, label: "Status",
  #              values: { active: "Active", terminated: "Terminated" }
  #     d.facet  :status, flag: :is
  #     d.sort   :best, default: true
  #   end
  class Definition
    Index = Data.define(:key, :name)
    Text = Data.define(:key, :attributes, :sensitive, :default, :label, :mask)
    FilterOperator = Data.define(:key, :attribute, :sensitive, :normalize, :format, :label, :mask)
    Flags = Data.define(:key, :aliases, :attribute, :values, :rules, :label)
    # values: for a flag facet, the flag values it shows (nil: all of them).
    # top: filter-facet values loaded; show: how many show before "Find…";
    # search: a "Find…" box filtering the loaded values in the browser.
    Facet = Data.define(:key, :label, :flag, :filter, :top, :values, :show, :search)
    Sort = Data.define(:key, :label, :by, :default)
    # stage: :query_filter (returns a Filter per index, ANDed into every query)
    # or :results (transforms the page of hits). cardinality (results only):
    # :preserving (keeps every hit) or :changing (drops or merges hits).
    Hook = Data.define(:stage, :reference, :cardinality)
    Example = Data.define(:query, :description)
    # A checkbox in the options panel standing for exact query text (e.g. "-is:terminated").
    Option = Data.define(:key, :label, :text)
    # Options panel layout. A row is :inputs (one input per operator, or one
    # shared input when `bare`: its value is written unprefixed and read by
    # the interpreter), :flags (checkboxes) or :options (Option checkboxes).
    PanelGroup = Data.define(:label, :rows)
    # Hits sharing `attribute` are one group (e.g. a person); `valid` (callable
    # or class name) rejects values that must not group; `limit` caps "more
    # records" and the preview.
    # order: attributes => :asc/:desc for a group's records, the same on the
    # page, in "more records" and in the preview (nil: relevance order).
    GroupBy = Data.define(:attribute, :valid, :limit, :order)
    # values: for a :flags row, the flag values it shows (nil: all of them).
    # masked: an operator in the row masks its values (mask other than :none):
    # the field starts empty and hides what is typed.
    PanelRow = Data.define(:label, :keys, :kind, :bare, :masked, :values) do
      # @return [String] the compose field name (unique per row, also when two
      #   rows show different values of one flag family)
      def name
        return keys.join("_or_") if bare
        return "#{keys.first}-#{values.join("-")}" if values

        keys.first.to_s
      end
    end
    HOOK_STAGES = %i[query_filter results].freeze

    NORMALIZERS = {
      digits: ->(value) { value.delete("^0-9") },
      upcase: ->(value) { value.upcase },
      downcase: ->(value) { value.downcase },
      strip: ->(value) { value.strip }
    }.freeze
    MASKS = %i[none all last4 count].freeze

    attr_reader :name, :indexes, :texts, :filters, :flags, :facets, :sorts, :per_options, :retrieve, :highlight, :hooks, :group,
      :saved_store, :min_text_length, :parked

    # @param name [Symbol]
    # @yieldparam builder [Querylane::Definition::Builder]
    # @return [Querylane::Definition] frozen and validated
    def self.build(name, &)
      builder = Builder.new
      yield builder
      new(name, builder).freeze
    end

    # Operator by key or alias (case-insensitive), or nil.
    #
    # @return [Text, FilterOperator, Flags, nil]
    def operator(key)
      @operators[key.to_s.downcase]
    end

    # @return [Array<String>] every key and alias, for "did you mean"
    def operator_keys = @operators.keys

    # @return [Text] where bare words go
    def default_text = texts.find(&:default) || texts.first

    # @return [Facet, nil]
    def facet(key) = facets.find { |facet| facet.key.to_s == key.to_s }

    # The values a flag facet or flags panel row shows.
    #
    # @param flags [Flags]
    # @param subset [Array<Symbol>, nil]
    # @return [Hash{Symbol => String}] value → label
    def flag_values(flags, subset)
      subset ? flags.values.slice(*subset) : flags.values
    end

    # @return [Sort]
    def sort(key) = sorts.find { |sort| sort.key.to_s == key.to_s } || default_sort

    def default_sort = sorts.find(&:default) || sorts.first

    # Reads a bare token as an operator, e.g. "5432" → [:last4, "5432"].
    #
    # @return [Array(Symbol, String), nil]
    def interpret(token)
      return unless @interpreter

      resolve(@interpreter).call(token)
    end

    # Other readings of a bare token, offered as "… instead" on its chip.
    # The interpreter may answer `alternatives(token)` → [[key, value], …].
    #
    # @return [Array<Array(Symbol, String)>]
    def alternatives(token)
      interpreter = @interpreter && resolve(@interpreter)
      return [] unless interpreter.respond_to?(:alternatives)

      Array(interpreter.alternatives(token))
    end

    # @return [Array<Example>] shown on first load and in syntax help
    attr_reader :examples

    # @return [Array<Option>] options-panel checkboxes
    attr_reader :options

    # @return [Option, nil]
    def option(key) = options.find { |option| option.key.to_s == key.to_s }

    # @return [Array<PanelGroup>] the options panel; one group of every
    #   operator and option unless the host declared `d.panel` groups
    attr_reader :panel

    # The group value of a document, or nil when it has none or it is invalid.
    #
    # @param document [Hash]
    # @return [String, nil]
    def group_value(document)
      return unless group

      value = document[group.attribute].presence&.to_s
      value if value && (group.valid.nil? || resolve(group.valid).call(value))
    end

    # @return [Object, nil] the host's saved-search store (class names resolved per call)
    def saved_searches = saved_store && resolve(saved_store)

    # @return [Array<PanelRow>]
    def panel_rows = panel.flat_map(&:rows)

    # The filter one flag value stands for on one index.
    #
    # @param flags [Flags]
    # @param value [Symbol]
    # @param index [Symbol]
    # @return [Querylane::Filter]
    def flag_filter(flags, value, index:)
      if flags.rules
        resolve(flags.rules).public_send(value, index: index)
      else
        Filter.eq(flags.attribute, value.to_s)
      end
    end

    # @param stage [Symbol] :query_filter or :results
    # @return [Array<Hook>] in declaration order
    def hooks_for(stage) = hooks.select { |hook| hook.stage == stage }

    # The callable behind a hook (class names resolved per call).
    def resolve_hook(hook) = resolve(hook.reference)

    # Backend index name for a logical index.
    #
    # @return [String]
    def index_name(key)
      index = indexes.find { |candidate| candidate.key == key.to_sym } || raise(ConfigurationError, "Unknown index #{key}")
      index.name.respond_to?(:call) ? index.name.call : index.name
    end

    private

    def initialize(name, builder)
      @name = name.to_sym
      @indexes = builder.indexes.freeze
      @texts = builder.texts.freeze
      @filters = builder.filters.freeze
      @flags = builder.flag_families.freeze
      @facets = builder.facets.freeze
      @sorts = (builder.sorts.presence || [Sort.new(:best, "Best match", nil, true)]).freeze
      @per_options = (builder.per_options.presence || [25, 50, 100]).freeze
      @retrieve = builder.retrieve&.map(&:to_s)&.freeze
      @highlight = (builder.highlight || texts.flat_map(&:attributes)).map(&:to_s).freeze
      @interpreter = builder.interpreter
      @hooks = builder.hooks.freeze
      @examples = builder.examples.freeze
      @options = builder.options.freeze
      @group = builder.group_by
      @saved_store = builder.saved_store
      @min_text_length = builder.min_text_length
      @parked = builder.parked_keys.map(&:to_s).freeze
      @operators = index_operators
      @panel = (builder.panel_groups.presence || [default_panel_group]).map { |group| build_group(group) }.freeze
      validate!
    end

    def index_operators
      (texts + filters + flags).each_with_object({}) do |operator, all|
        keys = [operator.key, *(operator.respond_to?(:aliases) ? operator.aliases : [])]
        keys.each do |key|
          raise ConfigurationError, "#{@name}: operator #{key} defined twice" if all.key?(key.to_s)

          all[key.to_s] = operator
        end
      end.freeze
    end

    def default_panel_group
      rows = (texts + filters + flags).map { |operator| [operator.key.to_s.humanize, [operator.key], false, nil] }
      rows << [nil, options.map(&:key), false, nil] if options.any?
      [nil, rows]
    end

    # [label, [[row_label, keys, {bare:}], ...]] → PanelGroup, checked against the operators
    def build_group((label, rows))
      PanelGroup.new(label, rows.map do |row_label, keys, bare, values|
        if keys.all? { |key| option(key) }
          PanelRow.new(row_label, keys, :options, false, false, nil)
        else
          operators = keys.map { |key| operator(key) || raise(ConfigurationError, "#{@name}: panel field #{key} is not an operator or option") }
          kind = operators.all?(Flags) ? :flags : :inputs
          raise ConfigurationError, "#{@name}: panel row #{row_label} mixes flags and inputs" if kind == :inputs && operators.any?(Flags)
          raise ConfigurationError, "#{@name}: panel row #{row_label} shows one flag family" if kind == :flags && operators.size > 1

          raise ConfigurationError, "#{@name}: panel row #{row_label} takes values: only for flags" if values && kind != :flags
          unknown = Array(values) - ((kind == :flags) ? operators.first.values.keys : [])
          raise ConfigurationError, "#{@name}: panel row #{row_label} has unknown values #{unknown.join(", ")}" if unknown.any?

          PanelRow.new(row_label, keys, kind, bare, operators.any? { |operator| operator.respond_to?(:mask) && operator.mask != :none }, values)
        end
      end.freeze)
    end

    def validate!
      raise ConfigurationError, "#{@name}: declare at least one index" if indexes.empty?
      raise ConfigurationError, "#{@name}: declare at least one text operator" if texts.empty?

      facets.each do |facet|
        target = facet.flag ? flags.find { |flag| flag.key == facet.flag } : filters.find { |filter| filter.key == facet.filter }
        raise ConfigurationError, "#{@name}: facet #{facet.key} points at nothing" unless target
        raise ConfigurationError, "#{@name}: facet #{facet.key} cannot use sensitive operator" if target.respond_to?(:sensitive) && target.sensitive
        next unless facet.values

        raise ConfigurationError, "#{@name}: facet #{facet.key} takes values: only with flag:" unless facet.flag
        unknown = facet.values - target.values.keys
        raise ConfigurationError, "#{@name}: facet #{facet.key} has unknown values #{unknown.join(", ")}" if unknown.any?
      end
      flags.each do |flag|
        raise ConfigurationError, "#{@name}: flags #{flag.key} need attribute: or rules:" unless flag.attribute || flag.rules
        raise ConfigurationError, "#{@name}: flags #{flag.key} take attribute: or rules:, not both" if flag.attribute && flag.rules
      end
      raise ConfigurationError, "#{@name}: only one default sort" if sorts.count(&:default) > 1
    end

    def resolve(reference)
      case reference
      when String then reference.constantize
      when Proc, Method then reference
      else reference
      end
    end

    # Collects declarations for Definition.build.
    class Builder
      attr_reader :indexes, :texts, :filters, :flag_families, :facets, :sorts, :per_options, :hooks, :examples, :options, :panel_groups,
        :group_by, :saved_store, :parked_keys

      # Attributes a searcher returns for each hit (server-side projection).
      def retrieve(*attributes)
        return @retrieve if attributes.empty?

        @retrieve = attributes.flatten
      end

      # Attributes highlighted in hits (default: the text attributes).
      def highlight(*attributes)
        return @highlight if attributes.empty?

        @highlight = attributes.flatten
      end

      # Reads bare tokens as operators: an object or class name responding to
      # call(token) → [operator_key, value] or nil. Rules are ordered by the host.
      def interpreter(reference = nil)
        return @interpreter if reference.nil?

        @interpreter = reference
      end

      def initialize
        @indexes = []
        @texts = []
        @filters = []
        @flag_families = []
        @facets = []
        @sorts = []
        @per_options = []
        @hooks = []
        @examples = []
        @options = []
        @panel_groups = []
        @parked_keys = []
      end

      # Operator names reserved for later: using one is an error that says
      # so ("first: is not available yet") instead of "not an operator".
      def parked(*keys)
        @parked_keys.concat(keys.flatten.map(&:to_sym))
      end

      # A group of options-panel rows, in order:
      #
      #   d.panel "Who" do |p|
      #     p.row "Name contains", :name
      #     p.row "Member ID or SSN", :id, :ssn, bare: true
      #   end
      def panel(label)
        group = PanelBuilder.new
        yield group
        @panel_groups << [label, group.rows]
      end

      # Words shorter than this, with no filter in the query, do not search
      # (prefix matching on one or two letters matches most of an index).
      def min_text_length(length = nil)
        return @min_text_length if length.nil?

        @min_text_length = length
      end

      # Saved searches, kept by the host's store (see Querylane::Saving).
      def saved(store:)
        @saved_store = store
      end

      # Groups hits by an attribute every index carries (e.g. a person's ID):
      # rows are grouped on the page, and a group can load all its records.
      def group(attribute, valid: nil, limit: 20, order: nil)
        @group_by = GroupBy.new(attribute.to_s, valid, limit, order&.transform_keys(&:to_s)&.freeze)
      end

      # An options-panel checkbox that writes exact text, e.g.
      # option :exclude_terminated, "Exclude terminated", "-is:terminated".
      def option(key, label, text)
        @options << Option.new(key.to_sym, label, text)
      end

      # An example query with what it finds (first-load state, syntax help).
      def example(query, description)
        @examples << Example.new(query, description)
      end

      # Registers a hook. Query-filter hooks respond to
      # `call(index:, context:)` → Querylane::Filter; results hooks to
      # `call(hits:, context:)` → Array<Querylane::Result::Hit> (a subset of
      # the hits, in order, or hits merged with `contributors`). Reference is
      # an object or a class name (resolved per call, reload-safe).
      def hook(stage, reference, cardinality: :preserving)
        raise ConfigurationError, "Unknown hook stage #{stage}" unless HOOK_STAGES.include?(stage)
        raise ConfigurationError, "cardinality is :preserving or :changing" unless %i[preserving changing].include?(cardinality)

        @hooks << Hook.new(stage, reference, cardinality)
      end

      # A logical index and its backend name (a String or a callable).
      def index(key, name:)
        @indexes << Index.new(key.to_sym, name)
      end

      # A free-text operator. `label` may use %{value}; `mask` (for chips) as for filter.
      def text(key, attributes:, sensitive: false, default: false, label: nil, mask: nil)
        mask ||= sensitive ? :all : :none
        raise ConfigurationError, "Unknown mask #{mask}" unless MASKS.include?(mask)

        @texts << Text.new(key.to_sym, attributes.map(&:to_s), sensitive, default, label || "#{key.to_s.humanize} %{value}", mask)
      end

      # An exact-match operator. `normalize` runs before `format` is checked.
      # `mask` controls how chips show sensitive values: :none, :all, :last4, :count.
      def filter(key, attribute:, sensitive: false, normalize: nil, format: nil, label: nil, mask: nil)
        normalizer = normalize.is_a?(Symbol) ? NORMALIZERS.fetch(normalize) : normalize
        mask ||= sensitive ? :all : :none
        raise ConfigurationError, "Unknown mask #{mask}" unless MASKS.include?(mask)

        @filters << FilterOperator.new(key.to_sym, attribute.to_s, sensitive, normalizer, format, label || "#{key.to_s.humanize} %{value}", mask)
      end

      # A family of named values (`is:active`). Either `attribute:` (value
      # name = attribute value) or `rules:` (a class name whose methods take
      # `index:` and return a Querylane::Filter). `values` maps value → label.
      def flags(key, values:, alias: nil, attribute: nil, rules: nil, label: nil)
        aliases = Array(binding.local_variable_get(:alias)).map(&:to_sym)
        labels = values.is_a?(Hash) ? values.transform_keys(&:to_sym) : values.to_h { |value| [value.to_sym, value.to_s.humanize] }
        @flag_families << Flags.new(key.to_sym, aliases, attribute&.to_s, labels.freeze, rules, label || key.to_s.humanize)
      end

      # A facet over a flag family (counts per value) or a filter operator
      # (top N values by count).
      def facet(key, label: nil, flag: nil, filter: nil, top: 10, values: nil, show: nil, search: false)
        @facets << Facet.new(key.to_sym, label || key.to_s.humanize, flag&.to_sym, filter&.to_sym, top, values&.map(&:to_sym),
          show || top, search)
      end

      # `by` maps attributes to :asc/:desc; nil is relevance.
      def sort(key, label: nil, by: nil, default: false)
        @sorts << Sort.new(key.to_sym, label || key.to_s.humanize, by, default)
      end

      def per(*options)
        @per_options.concat(options.flatten)
      end
    end

    # Collects the rows of one `d.panel` group.
    class PanelBuilder
      attr_reader :rows

      def initialize
        @rows = []
      end

      # A labelled row of operators (or option keys). `bare: true` gives the
      # operators one shared input written without a prefix.
      # `values:` limits a flags row to some of its values (the rest stay in the box).
      def row(label, *keys, bare: false, values: nil)
        @rows << [label, keys.map(&:to_sym), bare, values&.map(&:to_sym)]
      end
    end
  end
end
